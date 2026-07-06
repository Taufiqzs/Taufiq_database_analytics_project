-- ==========================================================================
-- 05_views.sql — View Kemudahan Layer Gold
--
-- Tujuan:
--   Membuat SQL view di atas tabel silver dan gold untuk menyediakan
--   abstraksi yang ramah pengguna untuk pelaporan dan analisis ad-hoc.
--
-- View:
--   gold.vw_trip_enriched       – Setiap trip bersih dengan nama zona.
--   gold.vw_daily_trip_summary  – Alias untuk gold.daily_trip_summary.
--   gold.vw_zone_performance    – Ringkasan zona dengan jumlah dropoff.
-- ==========================================================================

-- ------------------------------------------------------------------
-- gold.vw_trip_enriched
--
-- Menggabungkan setiap trip bersih dengan detail zona pickup dan
-- dropoff (borough, nama zona, service_zone). Ini adalah view data
-- trip yang didenormalisasi dan ramah analis.
-- ------------------------------------------------------------------
CREATE OR REPLACE VIEW gold.vw_trip_enriched AS
SELECT
    t.trip_id,
    t.pickup_datetime,
    t.dropoff_datetime,
    t.pickup_date,
    t.pickup_hour,
    t.pickup_day_name,
    t.is_weekend,
    t.time_period,
    t.trip_duration_minutes,
    t.passenger_count,
    t.trip_distance,
    t.payment_type,
    t.payment_label,
    t.fare_amount,
    t.tip_amount,
    t.total_amount,
    pz.location_id AS pickup_location_id,
    pz.borough AS pickup_borough,
    pz.zone AS pickup_zone,
    pz.service_zone AS pickup_service_zone,
    dz.location_id AS dropoff_location_id,
    dz.borough AS dropoff_borough,
    dz.zone AS dropoff_zone,
    dz.service_zone AS dropoff_service_zone
FROM silver.taxi_trips_cleaned t
JOIN silver.taxi_zones pz ON pz.location_id = t.pickup_location_id
JOIN silver.taxi_zones dz ON dz.location_id = t.dropoff_location_id;

-- ------------------------------------------------------------------
-- gold.vw_daily_trip_summary
--
-- View passthrough sederhana di atas gold.daily_trip_summary.
-- Berguna untuk alat / ORM yang lebih suka view daripada tabel.
-- ------------------------------------------------------------------
CREATE OR REPLACE VIEW gold.vw_daily_trip_summary AS
SELECT *
FROM gold.daily_trip_summary;

-- ------------------------------------------------------------------
-- gold.vw_zone_performance
--
-- Memperluas gold.zone_performance_summary dengan kolom
-- total_dropoff_trips yang dihitung dari silver.taxi_trips_cleaned,
-- memberikan gambaran yang lebih lengkap tentang aktivitas setiap
-- zona (kedatangan dan keberangkatan).
-- ------------------------------------------------------------------
CREATE OR REPLACE VIEW gold.vw_zone_performance AS
SELECT
    z.location_id,
    z.borough,
    z.zone,
    z.total_pickup_trips,
    COALESCE(d.dropoff_trips, 0) AS total_dropoff_trips,
    z.total_revenue,
    z.avg_fare,
    z.avg_tip,
    z.avg_distance
FROM gold.zone_performance_summary z
LEFT JOIN (
    SELECT dropoff_location_id, COUNT(*) AS dropoff_trips
    FROM silver.taxi_trips_cleaned
    GROUP BY dropoff_location_id
) d ON d.dropoff_location_id = z.location_id;

