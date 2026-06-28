-- ============================================================================
-- app_update_config — manual DDL for PROD (imeterrecorder_db)
-- ----------------------------------------------------------------------------
-- Prod runs SPRING_JPA_HIBERNATE_DDL_AUTO=validate (security audit F25), so the
-- app-update feature's table must be created by reviewed DDL, not Hibernate.
-- This statement was generated AUTHORITATIVELY from the prod image entity via
-- jakarta.persistence schema-generation (Hibernate's own output) — column types
-- match exactly so schema-validation passes:
--   updated_at = datetimeoffset(6)  (NOT datetime2)
--   string cols = varchar           (NOT nvarchar)
-- Generated 2026-06-12 to resolve the app_update_config crash loop.
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'app_update_config')
BEGIN
    CREATE TABLE app_update_config (
        platform        varchar(16)        NOT NULL,
        target_version  varchar(32)        NOT NULL,
        mode            varchar(16)        NOT NULL,
        updated_at      datetimeoffset(6)  NOT NULL,
        updated_by      varchar(256)       NOT NULL,
        CONSTRAINT PK_app_update_config PRIMARY KEY (platform),
        CONSTRAINT CK_app_update_config_mode     CHECK (mode IN ('OFF','NOTIFY','FORCE')),
        CONSTRAINT CK_app_update_config_platform CHECK (platform IN ('ANDROID','IOS'))
    );
END;
