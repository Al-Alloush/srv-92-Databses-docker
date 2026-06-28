-- ============================================================================
-- meters — manual DDL for PROD (imeterrecorder_db)
-- ----------------------------------------------------------------------------
-- Second table the current prod image expects but prod never had (ddl-auto=
-- validate). DISTINCT from meter_devices (different columns) — not a rename, so
-- this is an additive create (meter_devices is empty; no data migration).
-- DDL generated authoritatively from the prod image entity via Hibernate
-- jakarta.persistence schema-generation. 2026-06-12.
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'meters')
BEGIN
    CREATE TABLE meters (
        id                     uniqueidentifier  NOT NULL,
        user_id                uniqueidentifier  NOT NULL,
        energy_type            varchar(20)       NOT NULL,
        meter_number           NVARCHAR(100),
        meter_name             NVARCHAR(150),
        version                int               NOT NULL,
        server_revision        bigint,
        deleted                bit,
        created_at             varchar(50)       NOT NULL,
        updated_at             varchar(50)       NOT NULL,
        client_modified_at     varchar(50),
        deleted_at             varchar(50),
        last_writer_device_id  varchar(100),
        CONSTRAINT PK_meters PRIMARY KEY (id)
    );
END;
