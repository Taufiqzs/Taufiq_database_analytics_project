-- ==========================================================================
-- 02_bronze_load.sql — Bronze Layer Clean-up
--
-- Purpose:
--   Truncates the bronze staging tables before the Python-based bulk load.
--
-- Notes:
--   - The actual data loading is performed by `scripts/load_to_postgres.py`
--     using pandas `to_sql`.
--   - This script ensures the bronze tables are empty and ready to receive
--     fresh data, making the pipeline idempotent (safe to re-run).
-- ==========================================================================

TRUNCATE TABLE bronze.raw_taxi_trips;
TRUNCATE TABLE bronze.raw_taxi_zones;

