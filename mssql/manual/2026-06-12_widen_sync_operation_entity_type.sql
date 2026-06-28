-- ============================================================================
-- sync_operation.entity_type — widen CHECK to include new meter sync types
-- ----------------------------------------------------------------------------
-- The meters/meter_devices feature adds entity_type values METER & METER_DEVICE.
-- Prod's old auto-named CHECK (CK__sync_oper__entit__...) lacked them, so the
-- startup MeterBackfillRunner's sync_operation INSERTs were rejected. Hibernate
-- doesn't validate CHECK contents, so the app booted but the backfill failed.
-- Widening only (superset) — existing rows already comply. Values match the
-- prod image entity exactly. 2026-06-12.
--
-- NOT YET APPLIED to prod — pending user approval (modifies an existing table).
-- ============================================================================
DECLARE @ck sysname;
SELECT @ck = cc.name
FROM sys.check_constraints cc
JOIN sys.columns c ON cc.parent_object_id = c.object_id AND cc.parent_column_id = c.column_id
WHERE OBJECT_NAME(cc.parent_object_id) = 'sync_operation' AND c.name = 'entity_type';

IF @ck IS NOT NULL
    EXEC('ALTER TABLE sync_operation DROP CONSTRAINT [' + @ck + ']');

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_sync_operation_entity_type')
    ALTER TABLE sync_operation WITH CHECK ADD CONSTRAINT CK_sync_operation_entity_type
        CHECK (entity_type IN ('CHART_CONFIGURATION','CONTRACT','METER','METER_DEVICE','METER_READING','REMINDER','USAGE_DATA_POINT','USER_SETTING'));
