/* Run in SSMS in the database to inspect. SQL Server 2016+.
   One result set. Matching values share a row listing their schemas.
   ANOMALY = a value differing from a strict majority; DIFFERENT = no majority.
   Definitions are compared as stored text. Column position is also compared.
   Table/column presence is reported separately from definition properties.
   Run with VIEW DEFINITION access to all five schemas.
*/
;WITH Schemas AS
(
    SELECT SchemaName
    FROM (VALUES
        (N'billadmin')
    ) AS s(SchemaName)
),
Tables AS
(
    SELECT s.SchemaName, t.name COLLATE Latin1_General_100_BIN2 AS TableName,
           t.object_id, t.schema_id, t.uses_ansi_nulls,
           t.lock_escalation_desc, t.is_memory_optimized, t.durability_desc,
           t.temporal_type_desc, t.large_value_types_out_of_row,
           t.text_in_row_limit, t.is_filetable,
           t.is_replicated, t.has_replication_filter,
           t.is_merge_published, t.is_schema_published
    FROM sys.tables AS t
    JOIN sys.schemas AS ss ON ss.schema_id = t.schema_id
    JOIN Schemas AS s ON s.SchemaName = ss.name
    WHERE t.is_ms_shipped = 0
),
Columns AS
(
    SELECT t.SchemaName, t.TableName,
           c.name COLLATE Latin1_General_100_BIN2 AS ColumnName,
           c.max_length, c.precision, c.scale, c.is_nullable, c.collation_name,
           c.is_ansi_padded, c.is_identity, c.is_computed, c.is_rowguidcol,
           c.is_filestream, c.is_sparse, c.is_column_set, c.is_xml_document,
           c.generated_always_type_desc, c.is_hidden, c.is_masked,
           c.encryption_type_desc, c.encryption_algorithm_name,
           cek.name AS EncryptionKeyName,
           CASE WHEN c.encryption_type IS NOT NULL
                THEN COALESCE(c.column_encryption_key_database_name, DB_NAME()) END AS EncryptionKeyDatabase,
           ROW_NUMBER() OVER (PARTITION BY c.object_id ORDER BY c.column_id) AS ColumnPosition,
           ut.name AS DataType, bt.name AS BaseDataType,
           CASE WHEN ut.is_user_defined = 1 OR ut.is_assembly_type = 1
                THEN CASE WHEN ut.schema_id = t.schema_id THEN N'<own schema>'
                          ELSE SCHEMA_NAME(ut.schema_id) END END AS TypeSchema,
           CONVERT(nvarchar(100), ic.seed_value) AS IdentitySeed,
           CONVERT(nvarchar(100), ic.increment_value) AS IdentityIncrement,
           ic.is_not_for_replication AS IdentityNotForReplication,
           cc.definition AS ComputedDefinition, cc.is_persisted,
           OBJECT_DEFINITION(c.default_object_id) AS DefaultDefinition,
           OBJECT_DEFINITION(c.rule_object_id) AS BoundRuleDefinition,
           CASE WHEN xc.xml_collection_id IS NOT NULL
                THEN QUOTENAME(CASE WHEN xc.schema_id = t.schema_id
                                    THEN N'<own schema>' ELSE SCHEMA_NAME(xc.schema_id) END)
                     + N'.' + QUOTENAME(xc.name) END AS XmlSchemaCollection,
           mc.masking_function,
           c.is_replicated, c.is_non_sql_subscribed,
           c.is_merge_published, c.is_dts_replicated
    FROM Tables AS t
    JOIN sys.columns AS c ON c.object_id = t.object_id
    JOIN sys.types AS ut ON ut.user_type_id = c.user_type_id
    LEFT JOIN sys.types AS bt
        ON bt.system_type_id = c.system_type_id AND bt.user_type_id = bt.system_type_id
    LEFT JOIN sys.identity_columns AS ic
        ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    LEFT JOIN sys.computed_columns AS cc
        ON cc.object_id = c.object_id AND cc.column_id = c.column_id
    LEFT JOIN sys.xml_schema_collections AS xc
        ON xc.xml_collection_id = NULLIF(c.xml_collection_id, 0)
    LEFT JOIN sys.masked_columns AS mc
        ON mc.object_id = c.object_id AND mc.column_id = c.column_id
    LEFT JOIN sys.column_encryption_keys AS cek
        ON cek.column_encryption_key_id = c.column_encryption_key_id
       AND (c.column_encryption_key_database_name IS NULL OR c.column_encryption_key_database_name = DB_NAME())
),
RawProperties AS
(
    -- Table presence: include every table found in ANY of the five schemas.
    SELECT s.SchemaName, k.TableName,
           CAST(NULL AS nvarchar(128)) COLLATE Latin1_General_100_BIN2 AS ColumnName,
           N'TableExists' AS Property,
           CONVERT(nvarchar(max), CASE WHEN t.object_id IS NULL
                                      THEN N'MISSING' ELSE N'PRESENT' END) AS Value
    FROM Schemas AS s
    CROSS JOIN (SELECT DISTINCT TableName FROM Tables) AS k
    LEFT JOIN Tables AS t ON t.SchemaName = s.SchemaName AND t.TableName = k.TableName

    UNION ALL

    -- Table properties apply to the schemas where the table exists.
    SELECT t.SchemaName, t.TableName, NULL, p.Property,
           p.Value COLLATE Latin1_General_100_BIN2
    FROM Tables AS t
    CROSS APPLY (VALUES
        (N'ColumnCount', CONVERT(nvarchar(max), (SELECT COUNT(*) FROM sys.columns AS c WHERE c.object_id = t.object_id))),
        (N'AnsiNulls', CONVERT(nvarchar(max), t.uses_ansi_nulls)),
        (N'LockEscalation', CONVERT(nvarchar(max), t.lock_escalation_desc)),
        (N'MemoryOptimized', CONVERT(nvarchar(max), t.is_memory_optimized)),
        (N'Durability', CONVERT(nvarchar(max), t.durability_desc)),
        (N'TemporalType', CONVERT(nvarchar(max), t.temporal_type_desc)),
        (N'LargeValuesOutOfRow', CONVERT(nvarchar(max), t.large_value_types_out_of_row)),
        (N'TextInRowLimit', CONVERT(nvarchar(max), t.text_in_row_limit)),
        (N'FileTable', CONVERT(nvarchar(max), t.is_filetable)),
        (N'Replicated', CONVERT(nvarchar(max), t.is_replicated)),
        (N'ReplicationFilter', CONVERT(nvarchar(max), t.has_replication_filter)),
        (N'MergePublished', CONVERT(nvarchar(max), t.is_merge_published)),
        (N'SchemaPublished', CONVERT(nvarchar(max), t.is_schema_published))
    ) AS p(Property, Value)

    UNION ALL

    -- Column presence: missing parent tables are covered by TableExists.
    SELECT s.SchemaName, k.TableName, k.ColumnName, N'ColumnExists',
           CONVERT(nvarchar(max), CASE WHEN c.ColumnName IS NULL
                                      THEN N'MISSING' ELSE N'PRESENT' END)
    FROM Schemas AS s
    CROSS JOIN (SELECT DISTINCT TableName, ColumnName FROM Columns) AS k
    JOIN Tables AS t ON t.SchemaName = s.SchemaName AND t.TableName = k.TableName
    LEFT JOIN Columns AS c
        ON c.SchemaName = s.SchemaName AND c.TableName = k.TableName AND c.ColumnName = k.ColumnName

    UNION ALL

    -- Column properties apply to the schemas where the column exists.
    SELECT c.SchemaName, c.TableName, c.ColumnName, p.Property,
           p.Value COLLATE Latin1_General_100_BIN2
    FROM Columns AS c
    CROSS APPLY (VALUES
        (N'DataType', CONVERT(nvarchar(max), c.DataType)),
        (N'TypeSchema', CONVERT(nvarchar(max), c.TypeSchema)),
        (N'BaseDataType', CONVERT(nvarchar(max), c.BaseDataType)),
        (N'ColumnPosition', CONVERT(nvarchar(max), c.ColumnPosition)),
        (N'MaxLengthBytes', CONVERT(nvarchar(max), c.max_length)),
        (N'Precision', CONVERT(nvarchar(max), c.precision)),
        (N'Scale', CONVERT(nvarchar(max), c.scale)),
        (N'Nullable', CONVERT(nvarchar(max), c.is_nullable)),
        (N'Collation', CONVERT(nvarchar(max), c.collation_name)),
        (N'AnsiPadded', CONVERT(nvarchar(max), c.is_ansi_padded)),
        (N'Identity', CONVERT(nvarchar(max), c.is_identity)),
        (N'IdentitySeed', CONVERT(nvarchar(max), c.IdentitySeed)),
        (N'IdentityIncrement', CONVERT(nvarchar(max), c.IdentityIncrement)),
        (N'IdentityNotForReplication', CONVERT(nvarchar(max), c.IdentityNotForReplication)),
        (N'Computed', CONVERT(nvarchar(max), c.is_computed)),
        (N'ComputedDefinition', CONVERT(nvarchar(max), c.ComputedDefinition)),
        (N'Persisted', CONVERT(nvarchar(max), c.is_persisted)),
        (N'DefaultDefinition', CONVERT(nvarchar(max), c.DefaultDefinition)),
        (N'BoundRuleDefinition', CONVERT(nvarchar(max), c.BoundRuleDefinition)),
        (N'RowGuidColumn', CONVERT(nvarchar(max), c.is_rowguidcol)),
        (N'FileStream', CONVERT(nvarchar(max), c.is_filestream)),
        (N'Sparse', CONVERT(nvarchar(max), c.is_sparse)),
        (N'ColumnSet', CONVERT(nvarchar(max), c.is_column_set)),
        (N'XmlDocument', CONVERT(nvarchar(max), c.is_xml_document)),
        (N'XmlSchemaCollection', CONVERT(nvarchar(max), c.XmlSchemaCollection)),
        (N'GeneratedAlways', CONVERT(nvarchar(max), c.generated_always_type_desc)),
        (N'Hidden', CONVERT(nvarchar(max), c.is_hidden)),
        (N'Masked', CONVERT(nvarchar(max), c.is_masked)),
        (N'MaskingFunction', CONVERT(nvarchar(max), c.masking_function)),
        (N'EncryptionType', CONVERT(nvarchar(max), c.encryption_type_desc)),
        (N'EncryptionAlgorithm', CONVERT(nvarchar(max), c.encryption_algorithm_name)),
        (N'EncryptionKeyName', CONVERT(nvarchar(max), c.EncryptionKeyName)),
        (N'EncryptionKeyDatabase', CONVERT(nvarchar(max), c.EncryptionKeyDatabase)),
        (N'Replicated', CONVERT(nvarchar(max), c.is_replicated)),
        (N'NonSqlSubscribed', CONVERT(nvarchar(max), c.is_non_sql_subscribed)),
        (N'MergePublished', CONVERT(nvarchar(max), c.is_merge_published)),
        (N'DtsReplicated', CONVERT(nvarchar(max), c.is_dts_replicated))
    ) AS p(Property, Value)
),
Properties AS
(
    SELECT SchemaName, TableName, ColumnName, Property,
           Value COLLATE Latin1_General_100_BIN2 AS Value
    FROM RawProperties
),
Grouped AS
(
    SELECT TableName, ColumnName, Property, Value,
           COUNT(*) AS SchemaCount,
           STUFF(
               MAX(CASE WHEN SchemaName = N'wmwhse1' THEN N', wmwhse1' ELSE N'' END) +
               MAX(CASE WHEN SchemaName = N'wmwhse2' THEN N', wmwhse2' ELSE N'' END) +
               MAX(CASE WHEN SchemaName = N'wmwhse3' THEN N', wmwhse3' ELSE N'' END) +
               MAX(CASE WHEN SchemaName = N'wmwhse4' THEN N', wmwhse4' ELSE N'' END) +
               MAX(CASE WHEN SchemaName = N'wmwhse5' THEN N', wmwhse5' ELSE N'' END),
               1, 2, N'') AS Schemas
    FROM Properties
    GROUP BY TableName, ColumnName, Property, Value, DATALENGTH(Value)
),
Compared AS
(
    SELECT *,
           COUNT(*) OVER (PARTITION BY TableName, ColumnName, Property) AS ValueVariants,
           SUM(SchemaCount) OVER (PARTITION BY TableName, ColumnName, Property) AS TotalSchemas,
           MAX(SchemaCount) OVER (PARTITION BY TableName, ColumnName, Property) AS LargestGroup
    FROM Grouped
)
SELECT TableName,
       COALESCE(ColumnName, N'<TABLE>') AS ColumnName,
       Property,
       COALESCE(Value, N'<NULL / N.A.>') AS Value,
       SchemaCount,
       Schemas,
       CASE WHEN ValueVariants = 1 AND SchemaCount = 5 THEN N'SAME'
            WHEN ValueVariants = 1 THEN N'SAME WHERE PRESENT'
            WHEN SchemaCount * 2 > TotalSchemas THEN N'COMMON'
            WHEN LargestGroup * 2 > TotalSchemas THEN N'ANOMALY'
            ELSE N'DIFFERENT' END AS Status
FROM Compared
ORDER BY TableName, ColumnName, Property, SchemaCount DESC, Value;
