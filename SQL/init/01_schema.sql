-- ==========================================================================
-- 01_schema.sql — Database Schema Definition
--
-- Purpose:
--   Defines the complete database schema for the NYC Taxi Analytics
--   pipeline. Creates all schemas (bronze, silver, gold, audit) and
--   their corresponding tables.
--
-- Schema overview:
--   audit  – Pipeline run logging and load-audit records.
--   bronze – Staging tables that mirror the raw input files (Parquet/CSV).
--   silver – Cleaned, validated, and enriched trip & zone data.
--   gold   – Aggregated summary marts for reporting (created in 04_gold_mart.sql).
--
-- Idempotent: Uses IF NOT EXISTS so it can be run safely multiple times.
-- ==========================================================================

-- ------------------------------------------------------------------
-- Layer schemas
-- ------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;
CREATE SCHEMA IF NOT EXISTS audit;

-- ------------------------------------------------------------------
-- audit.pipeline_run
--
-- Records the status and timing of each pipeline execution.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit.pipeline_run (
    run_id      BIGSERIAL PRIMARY KEY,
    run_name    TEXT NOT NULL,
    status      TEXT NOT NULL CHECK (status IN ('STARTED', 'SUCCESS', 'FAILED')),
    started_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMPTZ,
    message     TEXT
);

-- ------------------------------------------------------------------
-- audit.load_audit
--
-- Captures per-step details for a pipeline run: which layer/object was
-- loaded, how many rows were processed, and whether the step succeeded.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit.load_audit (
    audit_id    BIGSERIAL PRIMARY KEY,
    run_id      BIGINT REFERENCES audit.pipeline_run(run_id),
    layer_name  TEXT NOT NULL,
    object_name TEXT NOT NULL,
    row_count   BIGINT NOT NULL CHECK (row_count >= 0),
    status      TEXT NOT NULL CHECK (status IN ('SUCCESS', 'FAILED')),
    message     TEXT,
    logged_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------------
-- bronze.raw_taxi_trips
--
-- Staging table for yellow taxi trip records as loaded from the
-- NYC TLC Parquet file. No transformations are applied at this stage;
-- the data is stored in its raw form (including potential quality issues).
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.raw_taxi_trips (
    vendor_id              INTEGER,
    tpep_pickup_datetime   TIMESTAMP,
    tpep_dropoff_datetime  TIMESTAMP,
    passenger_count        NUMERIC,
    trip_distance          NUMERIC,
    ratecode_id            NUMERIC,
    store_and_fwd_flag     TEXT,
    pu_location_id         INTEGER,
    do_location_id         INTEGER,
    payment_type           BIGINT,
    fare_amount            NUMERIC,
    extra                  NUMERIC,
    mta_tax                NUMERIC,
    tip_amount             NUMERIC,
    tolls_amount           NUMERIC,
    improvement_surcharge  NUMERIC,
    total_amount           NUMERIC,
    congestion_surcharge   NUMERIC,
    airport_fee            NUMERIC,
    cbd_congestion_fee     NUMERIC,
    source_file            TEXT NOT NULL,
    loaded_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------------
-- bronze.raw_taxi_zones
--
-- Staging table for the NYC TLC taxi zone lookup CSV data.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.raw_taxi_zones (
    location_id  INTEGER,
    borough      TEXT,
    zone         TEXT,
    service_zone TEXT,
    source_file  TEXT NOT NULL,
    loaded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------------
-- silver.taxi_zones
--
-- Cleaned and deduplicated taxi zone reference table.
-- Each location_id acts as a foreign-key target for trip records.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.taxi_zones (
    location_id  INTEGER PRIMARY KEY,
    borough      TEXT NOT NULL,
    zone         TEXT NOT NULL,
    service_zone TEXT NOT NULL
);

-- ------------------------------------------------------------------
-- silver.taxi_trips_cleaned
--
-- Validated taxi trips that passed all quality checks. Derived columns
-- such as pickup_date, pickup_hour, day name, time_period, and
-- trip_duration_minutes are pre-computed for analytical convenience.
-- A unique constraint prevents duplicate loading.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.taxi_trips_cleaned (
    trip_id              BIGSERIAL PRIMARY KEY,
    vendor_id            INTEGER,
    pickup_datetime      TIMESTAMP NOT NULL,
    dropoff_datetime     TIMESTAMP NOT NULL,
    pickup_date          DATE NOT NULL,
    pickup_hour          INTEGER NOT NULL CHECK (pickup_hour BETWEEN 0 AND 23),
    pickup_day_name      TEXT NOT NULL,
    is_weekend           BOOLEAN NOT NULL,
    time_period          TEXT NOT NULL,
    trip_duration_minutes NUMERIC(12, 2) NOT NULL CHECK (trip_duration_minutes > 0),
    passenger_count      INTEGER NOT NULL CHECK (passenger_count > 0),
    trip_distance        NUMERIC(12, 2) NOT NULL CHECK (trip_distance > 0),
    pickup_location_id   INTEGER NOT NULL REFERENCES silver.taxi_zones(location_id),
    dropoff_location_id  INTEGER NOT NULL REFERENCES silver.taxi_zones(location_id),
    payment_type         BIGINT NOT NULL,
    payment_label        TEXT NOT NULL,
    fare_amount          NUMERIC(12, 2) NOT NULL CHECK (fare_amount >= 0),
    tip_amount           NUMERIC(12, 2) NOT NULL CHECK (tip_amount >= 0),
    total_amount         NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0),
    loaded_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_taxi_trip_cleaned UNIQUE (
        vendor_id,
        pickup_datetime,
        dropoff_datetime,
        pickup_location_id,
        dropoff_location_id,
        passenger_count,
        trip_distance,
        total_amount
    )
);

-- ------------------------------------------------------------------
-- silver.data_quality_issues
--
-- Captures all records from bronze that failed validation rules during
-- the bronze → silver transformation. Each row stores the original
-- values alongside a descriptive error type for later analysis.
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.data_quality_issues (
    issue_id             BIGSERIAL PRIMARY KEY,
    error_type           TEXT NOT NULL,
    error_description    TEXT NOT NULL,
    vendor_id            INTEGER,
    pickup_datetime      TIMESTAMP,
    dropoff_datetime     TIMESTAMP,
    pickup_location_id   INTEGER,
    dropoff_location_id  INTEGER,
    passenger_count      NUMERIC,
    trip_distance        NUMERIC,
    fare_amount          NUMERIC,
    tip_amount           NUMERIC,
    total_amount         NUMERIC,
    source_file          TEXT,
    logged_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
