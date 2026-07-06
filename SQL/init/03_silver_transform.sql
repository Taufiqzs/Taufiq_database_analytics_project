-- ==========================================================================
-- 03_silver_transform.sql — Transformasi Bronze → Silver
--
-- Tujuan:
--   Mentransformasi data mentah bronze menjadi tabel layer silver yang
--   bersih dan tervalidasi. Skrip ini melakukan tiga operasi utama:
--
--   1. Memuat dan membersihkan data referensi zona taksi (silver.taxi_zones).
--   2. Memvalidasi setiap record trip bronze terhadap aturan kualitas;
--      record yang ditolak dicatat di silver.data_quality_issues.
--   3. Menyisipkan trip yang valid dan bersih ke silver.taxi_trips_cleaned
--      dengan kolom turunan yang telah dihitung (tanggal, jam, nama hari,
--      periode waktu, durasi, label pembayaran).
--
-- Idempoten: Memotong (truncate) tabel silver di awal sehingga aman
-- untuk dijalankan ulang.
-- ==========================================================================

-- ------------------------------------------------------------------
-- Langkah 0: Hapus data silver yang ada (dukungan idempoten untuk
-- dijalankan ulang)
-- ------------------------------------------------------------------
TRUNCATE TABLE silver.data_quality_issues RESTART IDENTITY;
TRUNCATE TABLE silver.taxi_trips_cleaned RESTART IDENTITY CASCADE;
TRUNCATE TABLE silver.taxi_zones CASCADE;

-- ------------------------------------------------------------------
-- Langkah 1: Memuat data referensi zona yang bersih
--
-- Menduplikasi dan membersihkan CSV zona mentah. Nilai string kosong
-- atau NULL diganti dengan 'Unknown'. Hanya record dengan location_id
-- tidak NULL yang disimpan.
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
-- Langkah 2: Validasi trip bronze dan catat masalah kualitas
--
-- CTE 'raw_checks' menggunakan ekspresi CASE yang memberikan error_type
-- pada setiap record yang melanggar aturan bisnis. Record yang lolos
-- semua pemeriksaan mendapat error_type = NULL dan tidak dimasukkan ke
-- silver.data_quality_issues.
--
-- Aturan validasi:
--   - pickup & dropoff datetime harus ada.
--   - Dropoff harus setelah pickup (durasi positif).
--   - passenger_count, trip_distance harus > 0.
--   - fare_amount, tip_amount, total_amount harus >= 0.
--   - ID lokasi pickup dan dropoff harus merujuk ke zona yang valid.
--   - Pickup datetime harus dalam rentang Januari 2026.
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
-- Langkah 3: Menyisipkan trip yang tervalidasi dan bersih
--
-- Hanya record yang lolos semua pemeriksaan validasi (kebalikan dari
-- CTE raw_checks di atas) yang dimasukkan. SELECT memperkaya setiap
-- baris dengan kolom turunan:
--
--   - pickup_date        : Tanggal yang diekstrak dari pickup_datetime.
--   - pickup_hour        : Jam (0–23).
--   - pickup_day_name    : Nama hari dalam Bahasa Inggris (mis. 'Monday').
--   - is_weekend         : TRUE jika ISODOW 6 (Sab) atau 7 (Min).
--   - time_period        : 'Morning' (5–10), 'Afternoon' (11–15),
--                          'Evening' (16–20), 'Night' (21–4).
--   - trip_duration_minutes : Durasi dalam menit (dibulatkan 2 desimal).
--   - payment_label      : Deskripsi metode pembayaran yang mudah dibaca.
--
-- Duplikat diabaikan secara diam-diam melalui ON CONFLICT DO NOTHING.
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

