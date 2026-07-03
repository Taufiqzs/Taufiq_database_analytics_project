-- ==========================================================================
-- 03_silver_transform.sql — Bronze → Silver Transformation
--
-- Purpose:
--   Transforms raw bronze data into clean, validated silver-layer tables.
--   This script performs three major operations:
--
--   1. Loads and cleans the taxi zone reference data (silver.taxi_zones).
--   2. Validates every bronze trip record against quality rules; rejected
--      records are logged in silver.data_quality_issues.
--   3. Inserts valid, cleaned trips into silver.taxi_trips_cleaned with
--      pre-computed derived columns (date, hour, day name, time period,
--      duration, payment label).
--
-- Idempotent: Truncates silver tables at the start so re-running is safe.
-- ==========================================================================

-- ------------------------------------------------------------------
-- Step 0: Clear existing silver data (idempotent re-run support)
-- ------------------------------------------------------------------
TRUNCATE TABLE silver.data_quality_issues RESTART IDENTITY;
TRUNCATE TABLE silver.taxi_trips_cleaned RESTART IDENTITY CASCADE;
TRUNCATE TABLE silver.taxi_zones CASCADE;

-- ------------------------------------------------------------------
-- Step 1: Load clean zone reference data
--
-- Deduplicates and cleans the raw zone CSV. Empty or NULL string values
-- are replaced with 'Unknown'. Only records with a non-NULL location_id
-- are kept.
-- ------------------------------------------------------------------
INSERT INTO silver.taxi_zones (location_id, borough, zone, service_zone)
SELECT DISTINCT
    location_id,
    COALESCE(NULLIF(TRIM(borough), ''), 'Unknown') AS borough,
    COALESCE(NULLIF(TRIM(zone), ''), 'Unknown') AS zone,
    COALESCE(NULLIF(TRIM(service_zone), ''), 'Unknown') AS service_zone
FROM bronze.raw_taxi_zones
WHERE location_id IS NOT NULL;

-- ------------------------------------------------------------------
-- Step 2: Validate bronze trips and log quality issues
--
-- The CTE 'raw_checks' applies a CASE expression that assigns an
-- error_type to each record that violates a business rule. Records
-- that pass all checks get error_type = NULL and are excluded from the
-- INSERT into silver.data_quality_issues.
--
-- Validation rules:
--   - Both pickup & dropoff datetimes must be present.
--   - Dropoff must occur after pickup (positive duration).
--   - passenger_count, trip_distance must be > 0.
--   - fare_amount, tip_amount, total_amount must be >= 0.
--   - Pickup and dropoff location IDs must reference valid zones.
--   - Pickup datetime must fall within January 2026.
-- ------------------------------------------------------------------
WITH raw_checks AS (
    SELECT
        r.*,
        EXTRACT(EPOCH FROM (tpep_dropoff_datetime - tpep_pickup_datetime)) / 60.0 AS duration_minutes,
        CASE
            WHEN tpep_pickup_datetime IS NULL OR tpep_dropoff_datetime IS NULL THEN 'missing_datetime'
            WHEN tpep_dropoff_datetime <= tpep_pickup_datetime THEN 'invalid_duration'
            WHEN passenger_count IS NULL OR passenger_count <= 0 THEN 'invalid_passenger_count'
            WHEN trip_distance IS NULL OR trip_distance <= 0 THEN 'invalid_trip_distance'
            WHEN fare_amount IS NULL OR fare_amount < 0 THEN 'negative_fare'
            WHEN tip_amount IS NULL OR tip_amount < 0 THEN 'negative_tip'
            WHEN total_amount IS NULL OR total_amount < 0 THEN 'negative_total_amount'
            WHEN pu_location_id IS NULL OR NOT EXISTS (
                SELECT 1 FROM silver.taxi_zones z WHERE z.location_id = r.pu_location_id
            ) THEN 'unknown_pickup_location'
            WHEN do_location_id IS NULL OR NOT EXISTS (
                SELECT 1 FROM silver.taxi_zones z WHERE z.location_id = r.do_location_id
            ) THEN 'unknown_dropoff_location'
            WHEN tpep_pickup_datetime < TIMESTAMP '2026-01-01'
              OR tpep_pickup_datetime >= TIMESTAMP '2026-02-01' THEN 'outside_january_2026'
            ELSE NULL
        END AS error_type
    FROM bronze.raw_taxi_trips r
)
INSERT INTO silver.data_quality_issues (
    error_type,
    error_description,
    vendor_id,
    pickup_datetime,
    dropoff_datetime,
    pickup_location_id,
    dropoff_location_id,
    passenger_count,
    trip_distance,
    fare_amount,
    tip_amount,
    total_amount,
    source_file
)
SELECT
    error_type,
    'Record rejected during bronze to silver validation' AS error_description,
    vendor_id,
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    pu_location_id,
    do_location_id,
    passenger_count,
    trip_distance,
    fare_amount,
    tip_amount,
    total_amount,
    source_file
FROM raw_checks
WHERE error_type IS NOT NULL;

-- ------------------------------------------------------------------
-- Step 3: Insert validated, cleaned trips
--
-- Only records that passed all validation checks (the inverse of the
-- raw_checks CTE above) are inserted. The SELECT enriches each row
-- with derived columns:
--
--   - pickup_date        : Date extracted from pickup_datetime.
--   - pickup_hour        : Hour (0–23).
--   - pickup_day_name    : English day name (e.g. 'Monday').
--   - is_weekend         : TRUE if ISODOW is 6 (Sat) or 7 (Sun).
--   - time_period        : 'Morning' (5–10), 'Afternoon' (11–15),
--                          'Evening' (16–20), 'Night' (21–4).
--   - trip_duration_minutes : Duration in minutes (rounded to 2 decimals).
--   - payment_label      : Human-readable payment method description.
--
-- Duplicates are silently ignored via ON CONFLICT DO NOTHING.
-- ------------------------------------------------------------------
WITH valid_rows AS (
    SELECT
        vendor_id,
        tpep_pickup_datetime,
        tpep_dropoff_datetime,
        passenger_count::INTEGER AS passenger_count,
        ROUND(trip_distance::NUMERIC, 2) AS trip_distance,
        pu_location_id,
        do_location_id,
        COALESCE(payment_type, 0) AS payment_type,
        ROUND(COALESCE(fare_amount, 0)::NUMERIC, 2) AS fare_amount,
        ROUND(COALESCE(tip_amount, 0)::NUMERIC, 2) AS tip_amount,
        ROUND(COALESCE(total_amount, 0)::NUMERIC, 2) AS total_amount,
        ROUND((EXTRACT(EPOCH FROM (tpep_dropoff_datetime - tpep_pickup_datetime)) / 60.0)::NUMERIC, 2) AS duration_minutes
    FROM bronze.raw_taxi_trips r
    WHERE tpep_pickup_datetime IS NOT NULL
      AND tpep_dropoff_datetime IS NOT NULL
      AND tpep_dropoff_datetime > tpep_pickup_datetime
      AND passenger_count > 0
      AND trip_distance > 0
      AND fare_amount >= 0
      AND tip_amount >= 0
      AND total_amount >= 0
      AND tpep_pickup_datetime >= TIMESTAMP '2026-01-01'
      AND tpep_pickup_datetime < TIMESTAMP '2026-02-01'
      AND EXISTS (SELECT 1 FROM silver.taxi_zones z WHERE z.location_id = r.pu_location_id)
      AND EXISTS (SELECT 1 FROM silver.taxi_zones z WHERE z.location_id = r.do_location_id)
)
INSERT INTO silver.taxi_trips_cleaned (
    vendor_id,
    pickup_datetime,
    dropoff_datetime,
    pickup_date,
    pickup_hour,
    pickup_day_name,
    is_weekend,
    time_period,
    trip_duration_minutes,
    passenger_count,
    trip_distance,
    pickup_location_id,
    dropoff_location_id,
    payment_type,
    payment_label,
    fare_amount,
    tip_amount,
    total_amount
)
SELECT
    vendor_id,
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    tpep_pickup_datetime::DATE AS pickup_date,
    EXTRACT(HOUR FROM tpep_pickup_datetime)::INTEGER AS pickup_hour,
    TRIM(TO_CHAR(tpep_pickup_datetime, 'Day')) AS pickup_day_name,
    EXTRACT(ISODOW FROM tpep_pickup_datetime) IN (6, 7) AS is_weekend,
    CASE
        WHEN EXTRACT(HOUR FROM tpep_pickup_datetime) BETWEEN 5 AND 10 THEN 'Morning'
        WHEN EXTRACT(HOUR FROM tpep_pickup_datetime) BETWEEN 11 AND 15 THEN 'Afternoon'
        WHEN EXTRACT(HOUR FROM tpep_pickup_datetime) BETWEEN 16 AND 20 THEN 'Evening'
        ELSE 'Night'
    END AS time_period,
    duration_minutes,
    passenger_count,
    trip_distance,
    pu_location_id,
    do_location_id,
    payment_type,
    CASE payment_type
        WHEN 1 THEN 'Credit card'
        WHEN 2 THEN 'Cash'
        WHEN 3 THEN 'No charge'
        WHEN 4 THEN 'Dispute'
        WHEN 5 THEN 'Unknown'
        WHEN 6 THEN 'Voided trip'
        ELSE 'Other'
    END AS payment_label,
    fare_amount,
    tip_amount,
    total_amount
FROM valid_rows
ON CONFLICT ON CONSTRAINT uq_taxi_trip_cleaned DO NOTHING;

