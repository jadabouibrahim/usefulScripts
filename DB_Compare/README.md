Database Metadata Comparison

PropertiesQuery.sql
Reads table and column metadata from SQL Server for the selected schemas, including data types, lengths, nullability, defaults and other definition properties. Matching values are grouped together, while differences are listed with the affected schemas. The results can be exported from SSMS as CSV files.

compareResults.py
Compares the local and remote CSV exports and generates three reports: table differences, column differences and all differences combined. Identical changes across schemas are grouped together. Tables and columns missing in the remote database, along with column collation differences, are excluded.
