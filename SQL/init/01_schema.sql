-- ==========================================================================
-- 01_schema.sql — Definisi Skema Database
--
-- Tujuan:
--   Mendefinisikan skema database lengkap untuk pipeline NYC Taxi Analytics.
--   Membuat semua skema (bronze, silver, gold, audit) dan tabel-tabel yang
--   sesuai.
--
-- Ringkasan Skema:
--   audit  – Log eksekusi pipeline dan catatan audit load.
--   bronze – Tabel staging yang mencerminkan file input mentah (Parquet/CSV).
--   silver – Data perjalanan & zona yang dibersihkan, divalidasi, dan diperkaya.
--   gold   – Ringkasan mart teragregasi untuk pelaporan (dibuat di 04_gold_mart.sql).
--
-- Idempoten/idempotent: Menggunakan IF NOT EXISTS sehingga aman dijalankan berkali-kali.
-- ==========================================================================

-- ------------------------------------------------------------------
-- Skema layer
-- ------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;
CREATE SCHEMA IF NOT EXISTS audit;

-- ------------------------------------------------------------------
-- audit.pipeline_run
--
-- Mencatat status dan waktu setiap eksekusi pipeline.
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
-- Menangkap detail per-langkah untuk pipeline run: layer/objek mana yang
-- dimuat, berapa baris yang diproses, dan apakah langkah berhasil.
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
-- Tabel staging untuk data perjalanan taksi kuning yang dimuat dari
-- file Parquet NYC TLC. Tidak ada transformasi yang diterapkan;
-- data disimpan dalam bentuk mentah (termasuk potensi masalah kualitas).
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
-- Tabel staging untuk data CSV lookup zona taksi NYC TLC.
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
-- Tabel referensi zona taksi yang dibersihkan dan di-deduplikasi.
-- Setiap location_id bertindak sebagai target foreign key untuk data perjalanan.
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
-- Perjalanan taksi yang tervalidasi dan lolos semua pemeriksaan kualitas.
-- Kolom turunan seperti pickup_date, pickup_hour, nama hari, time_period,
-- dan trip_duration_minutes telah dihitung sebelumnya untuk kemudahan analisis.
-- Constraint unique mencegah pemuatan duplikat.
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
-- Menangkap semua data dari bronze yang gagal aturan validasi selama
-- transformasi bronze → silver. Setiap baris menyimpan nilai asli
-- beserta tipe error deskriptif untuk analisis selanjutnya.
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
