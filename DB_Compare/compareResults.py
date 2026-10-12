#!/usr/bin/env python3
"""Compare the CSVs produced by Grouped-Schema-Properties.sql.

Usage: python compare_grouped_reports.py local.csv remote.csv
       python compare_grouped_reports.py local.csv remote.csv --output results

LOCAL is the baseline. REMOTE is the database to check. Python 3.9+; no packages.
Creates three CSVs: remote-extra tables, column differences, all differences.
Ignores tables and columns missing in REMOTE, and column Collation differences.
Each row groups schemas with the same change. Status from the SQL report is
ignored: comparisons use the actual property values for each schema.
"""
from __future__ import annotations

import argparse
import codecs
import csv
import sys
from collections import Counter, defaultdict
from pathlib import Path

# Set this to the schema(s) included in both CSV exports.
#SCHEMAS = ("billadmin",)
# Accept a single string too, so ("billadmin") does not become individual letters.

#Uncomment this when comparing warehouses, make sure to update the schema count 
SCHEMAS = tuple(f'wmwhse{i}' for i in range(1, 6))
if isinstance(SCHEMAS, str):
    SCHEMAS = (SCHEMAS,)
SCHEMAS = tuple(schema.strip().lower() for schema in SCHEMAS)
HEADERS = ('TableName', 'ColumnName', 'Property', 'Value', 'SchemaCount', 'Schemas', 'Status')
OUTPUT_HEADERS = ('Category', 'Difference', 'TableName', 'ColumnName', 'Property',
                  'LocalValue', 'RemoteValue', 'Schemas', 'SchemaCount')
KNOWN_PROPERTIES = set('''
TableExists ColumnExists ColumnCount AnsiNulls LockEscalation MemoryOptimized
Durability TemporalType LargeValuesOutOfRow TextInRowLimit FileTable Replicated
ReplicationFilter MergePublished SchemaPublished DataType TypeSchema BaseDataType
ColumnPosition MaxLengthBytes Precision Scale Nullable Collation AnsiPadded Identity
IdentitySeed IdentityIncrement IdentityNotForReplication Computed ComputedDefinition
Persisted DefaultDefinition BoundRuleDefinition RowGuidColumn FileStream Sparse
ColumnSet XmlDocument XmlSchemaCollection GeneratedAlways Hidden Masked
MaskingFunction EncryptionType EncryptionAlgorithm EncryptionKeyName
EncryptionKeyDatabase NonSqlSubscribed DtsReplicated
'''.split())
MISSING = object()


def input_encoding(path, requested):
    if requested != 'auto':
        return requested
    with path.open('rb') as stream:
        prefix = stream.read(4)
    if prefix.startswith(codecs.BOM_UTF32_LE) or prefix.startswith(codecs.BOM_UTF32_BE):
        return 'utf-32'
    if prefix.startswith(codecs.BOM_UTF16_LE) or prefix.startswith(codecs.BOM_UTF16_BE):
        return 'utf-16'
    if prefix[1:4:2] == b'\x00\x00':
        return 'utf-16-le'
    if prefix[0:4:2] == b'\x00\x00':
        return 'utf-16-be'
    return 'utf-8-sig'


def repair_ssms_row(fields, delimiter):
    """Handle SSMS CSV output with unquoted commas in Value/Schemas.

    Recovery is restricted to the known seven-column layout, known property
    names, an exact schema-list suffix and its matching count. Valid quoted
    CSV takes the normal path without any recovery.
    """
    if delimiter != ',' or len(fields) <= len(HEADERS) or fields[2] not in KNOWN_PROPERTIES:
        return None
    statuses = {'SAME', 'SAME WHERE PRESENT', 'COMMON', 'ANOMALY', 'DIFFERENT'}
    if fields[-1].strip() not in statuses:
        return None
    index = len(fields) - 2
    schemas = []
    while index >= 5 and fields[index].strip().lower() in SCHEMAS:
        schemas.insert(0, fields[index].strip().lower())
        index -= 1
    if index < 4 or not schemas or len(schemas) != len(set(schemas)):
        return None
    try:
        if int(fields[index]) != len(schemas):
            return None
    except ValueError:
        return None
    return fields[:3] + [','.join(fields[3:index]), fields[index],
                         ', '.join(schemas), fields[-1]]


def read_report(path, encoding='auto', delimiter=None):
    # Keys identify a property, whose values are expanded by schema.
    # Intern names to reduce memory usage on large WMS reports.
    properties = {}
    with path.open('r', encoding=input_encoding(path, encoding), newline='') as stream:
        first_line = stream.readline()
        if not first_line:
            raise ValueError(f'{path}: empty file; a CSV header is required.')
        separator = delimiter or max((',', ';', '\t'), key=first_line.count)
        stream.seek(0)
        reader = csv.reader(stream, delimiter=separator, strict=True)
        header = [h.strip().lstrip('\ufeff') for h in next(reader)]
        normalized = [h.casefold() for h in header]
        expected = [h.casefold() for h in HEADERS]
        if len(normalized) != len(set(normalized)) or set(normalized) != set(expected):
            raise ValueError(
                f'{path}: expected these seven CSV headers: {", ".join(HEADERS)}. '
                'Use the full grouped SQL report and include headers when saving.'
            )
        indexes = {name: normalized.index(name.casefold()) for name in HEADERS}
        for fields in reader:
            if not fields or not any(fields):
                continue
            where = f'{path}, CSV line {reader.line_num}'
            if len(fields) != len(header):
                repaired = repair_ssms_row(fields, separator) if normalized == expected else None
                if repaired is None:
                    raise ValueError(f'{where}: invalid CSV row. Preserve CSV quotes around values/schema lists.')
                fields = repaired
            row = {name: fields[index] for name, index in indexes.items()}
            table = sys.intern(row['TableName'])
            column = None if row['ColumnName'] == '<TABLE>' else sys.intern(row['ColumnName'])
            prop = sys.intern(row['Property'])
            if not table or not prop or column == '':
                raise ValueError(f'{where}: missing table, column or property name.')
            schemas = [s.strip().lower() for s in row['Schemas'].split(',')]
            if len(set(schemas)) != len(schemas) or any(s not in SCHEMAS for s in schemas):
                raise ValueError(
                    f'{where}: configured schemas are {list(SCHEMAS)}; '
                    f'CSV schemas are {schemas}. Names must match and contain no duplicates.'
                )
            try:
                count = int(row['SchemaCount'])
            except ValueError as error:
                raise ValueError(f'{where}: SchemaCount is not a number.') from error
            if count != len(schemas):
                raise ValueError(f'{where}: SchemaCount does not match the schema list.')
            key = (table, column, prop)
            values = properties.setdefault(key, {})
            for schema in schemas:
                if schema in values:
                    raise ValueError(f'{where}: duplicate value for {schema}, {table}, {column}, {prop}.')
                values[sys.intern(schema)] = row['Value']  # Preserve case, whitespace and SQL text.
    validate_report(properties, path)
    return properties


def validate_report(properties, path):
    # Reject incomplete presence groups instead of misreporting absent rows as
    # missing database objects. An entirely absent table has no entries at all.
    for (table, column, prop), values in properties.items():
        table_presence = properties.get((table, None, 'TableExists'))
        if table_presence is None:
            raise ValueError(f'{path}: TableExists rows are missing for {table}.')
        if prop == 'TableExists' and column is None:
            expected = set(SCHEMAS)
        elif prop == 'ColumnExists' and column is not None:
            expected = {s for s, value in table_presence.items() if value == 'PRESENT'}
        elif column is None:
            expected = {s for s, value in table_presence.items() if value == 'PRESENT'}
        else:
            column_presence = properties.get((table, column, 'ColumnExists'))
            if column_presence is None:
                raise ValueError(f'{path}: ColumnExists rows are missing for {table}.{column}.')
            expected = {s for s, value in column_presence.items() if value == 'PRESENT'}
        if set(values) != expected:
            raise ValueError(
                f'{path}: incomplete or inconsistent schema list for {table}, {column}, {prop}. '
                f'Expected schemas: {sorted(expected)}; CSV schemas: {sorted(values)}.'
            )
        if prop in ('TableExists', 'ColumnExists') and any(v not in ('PRESENT', 'MISSING') for v in values.values()):
            raise ValueError(f'{path}: {prop} must contain PRESENT or MISSING.')


def is_present(report, table, column, schema):
    prop = 'TableExists' if column is None else 'ColumnExists'
    return report.get((table, column, prop), {}).get(schema) == 'PRESENT'


def compare_reports(local, remote):
    grouped = defaultdict(list)

    def add(category, difference, table, column, prop, local_value, remote_value, schema):
        grouped[(category, difference, table, column, prop, local_value, remote_value)].append(schema)

    all_keys = local.keys() | remote.keys()
    tables = {key[0] for key in all_keys}
    for table in sorted(tables):
        for schema in SCHEMAS:
            left, right = is_present(local, table, None, schema), is_present(remote, table, None, schema)
            if right and not left:
                add('TABLE', 'EXTRA_IN_REMOTE', table, None,
                    'TableExists', 'MISSING', 'PRESENT', schema)

    columns = {(table, column) for table, column, _ in all_keys if column is not None}
    for table, column in sorted(columns):
        for schema in SCHEMAS:
            if not (is_present(local, table, None, schema) and is_present(remote, table, None, schema)):
                continue  # Compare columns only in tables present on both sides.
            left, right = is_present(local, table, column, schema), is_present(remote, table, column, schema)
            if right and not left:
                add('COLUMN', 'EXTRA_IN_REMOTE', table, column,
                    'ColumnExists', 'MISSING', 'PRESENT', schema)

    for table, column, prop in sorted(all_keys, key=lambda k: (k[0], k[1] or '', k[2])):
        if prop in ('TableExists', 'ColumnExists'):
            continue
        if column is not None and prop.casefold() == 'collation':
            continue
        key = (table, column, prop)
        for schema in SCHEMAS:
            if not (is_present(local, table, None, schema) and is_present(remote, table, None, schema)):
                continue
            if column is not None and not (is_present(local, table, column, schema)
                                           and is_present(remote, table, column, schema)):
                continue
            left = local.get(key, {}).get(schema, MISSING)
            right = remote.get(key, {}).get(schema, MISSING)
            if left == right:
                continue
            difference = ('PROPERTY_NOT_IN_REMOTE_REPORT' if right is MISSING else
                          'PROPERTY_ONLY_IN_REMOTE_REPORT' if left is MISSING else 'CHANGED_IN_REMOTE')
            add('TABLE_PROPERTY' if column is None else 'COLUMN_PROPERTY', difference,
                table, column, prop, '<NOT IN REPORT>' if left is MISSING else left,
                '<NOT IN REPORT>' if right is MISSING else right, schema)

    rows = []
    for (category, difference, table, column, prop, left, right), schemas in grouped.items():
        rows.append(dict(zip(OUTPUT_HEADERS, (category, difference, table, column or '<TABLE>',
                    prop, left, right, ', '.join(sorted(schemas)), len(schemas)))))
    return sorted(rows, key=lambda r: (r['TableName'], r['ColumnName'], r['Property'],
                                     r['Difference'], r['Schemas'], r['LocalValue'], r['RemoteValue']))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('local', type=Path, help='Local/reference CSV: baseline.')
    parser.add_argument('remote', type=Path, help='Remote CSV: database to check.')
    parser.add_argument('--output', type=Path, default=Path('comparison_results'), help='Output folder.')
    parser.add_argument('--encoding', default='auto', help='Input encoding; auto detects UTF-8/UTF-16 BOMs.')
    parser.add_argument('--delimiter', choices=(',', ';', '\t'), help='Input delimiter; detected from headers by default.')
    args = parser.parse_args(argv)
    try:
        local = read_report(args.local, args.encoding, args.delimiter)
        remote = read_report(args.remote, args.encoding, args.delimiter)
        rows = compare_reports(local, remote)
        outputs = (
            ('01_missing_tables.csv', [r for r in rows if r['Category'] == 'TABLE']),
            ('02_column_differences.csv', [r for r in rows if r['Category'] in ('COLUMN', 'COLUMN_PROPERTY')]),
            ('03_total_differences.csv', rows)
        )
        input_paths = {args.local.resolve(), args.remote.resolve()}
        if any((args.output / name).resolve() in input_paths for name, _ in outputs):
            raise ValueError('An output file would overwrite an input CSV; choose another output folder.')
        args.output.mkdir(parents=True, exist_ok=True)
        for name, contents in outputs:
            with (args.output / name).open('w', encoding='utf-8-sig', newline='') as stream:
                writer = csv.DictWriter(stream, fieldnames=OUTPUT_HEADERS)
                writer.writeheader()
                writer.writerows(contents)
        counts = Counter()
        for row in rows:
            counts[row['Category']] += row['SchemaCount']
        print(f'Extra tables in remote: {counts["TABLE"]}')
        print(f'Extra columns in remote: {counts["COLUMN"]}')
        print(f'Column property differences: {counts["COLUMN_PROPERTY"]}')
        print(f'Table property differences: {counts["TABLE_PROPERTY"]}')
        print(f'Total differences: {sum(counts.values())} (counted per schema/property).')
        print(f'Saved three CSVs in: {args.output.resolve()}')
        return 0
    except (OSError, ValueError, UnicodeError, LookupError, csv.Error) as error:
        print(f'Error: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    limit = sys.maxsize
    while True:
        try:
            csv.field_size_limit(limit)
            break
        except OverflowError:
            limit //= 10
    sys.exit(main())
