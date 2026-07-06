-- ==========================================================================
-- 04_gold_mart.sql — Mart Teragregasi Layer Gold
--
-- Tujuan:
--   Membangun layer gold (presentasi) dengan membuat tabel ringkasan
--   material dari data silver yang telah dibersihkan. Tabel-tabel ini
--   dioptimalkan untuk dashboard dan query analitis ad-hoc.
--
-- Tabel yang dibuat:
--   gold.daily_trip_summary        – Jumlah trip per hari, revenue, rata-rata.
--   gold.hourly_demand_summary     – Permintaan per jam & rincian revenue.
--   gold.zone_performance_summary  – Metrik pickup per zona.
--   gold.payment_behavior_summary  – Analisis metode pembayaran (rasio tip).
--   gold.route_performance_summary – Statistik rute pickup → dropoff.
--
-- Idempoten: Menghapus tabel/view gold yang ada terlebih dahulu,
-- kemudian membuat ulang.
-- ==========================================================================

-- ------------------------------------------------------------------
-- Langkah 0: Hapus objek yang ada (keadaan bersih untuk
-- dijalankan ulang secara idempoten)
-- ------------------------------------------------------------------
DROP VIEW IF EXISTS gold.vw_trip_enriched;
DROP VIEW IF EXISTS gold.vw_daily_trip_summary;
DROP VIEW IF EXISTS gold.vw_zone_performance;

DROP TABLE IF EXISTS gold.daily_trip_summary;
DROP TABLE IF EXISTS gold.hourly_demand_summary;
DROP TABLE IF EXISTS gold.zone_performance_summary;
DROP TABLE IF EXISTS gold.payment_behavior_summary;
DROP TABLE IF EXISTS gold.route_performance_summary;

-- ------------------------------------------------------------------
-- gold.daily_trip_summary
--
-- Satu baris per hari kalender dalam dataset.
-- Menyediakan total dan rata-rata harian untuk revenue, fare, tip,
-- jarak, dan durasi perjalanan.
-- ------------------------------------------------------------------
CREATE TABLE gold.daily_trip_summary AS
SELECT
    pickup_date,
    COUNT(*) AS total_trips,
    SUM(total_amount) AS total_revenue,
    AVG(total_amount) AS avg_revenue,
    AVG(fare_amount) AS avg_fare,
    AVG(tip_amount) AS avg_tip,
    AVG(trip_distance) AS avg_distance,
    AVG(trip_duration_minutes) AS avg_duration_minutes
FROM silver.taxi_trips_cleaned
GROUP BY pickup_date;

ALTER TABLE gold.daily_trip_summary ADD PRIMARY KEY (pickup_date);

-- ------------------------------------------------------------------
-- gold.hourly_demand_summary
--
-- Satu baris per kombinasi tanggal + jam. Termasuk label time_period
-- (Morning / Afternoon / Evening / Night) untuk pengelompokan yang
-- mudah.
-- ------------------------------------------------------------------
CREATE TABLE gold.hourly_demand_summary AS
SELECT
    pickup_date,
    pickup_hour,
    time_period,
    COUNT(*) AS total_trips,
    SUM(total_amount) AS total_revenue,
    AVG(trip_duration_minutes) AS avg_duration_minutes
FROM silver.taxi_trips_cleaned
GROUP BY pickup_date, pickup_hour, time_period;

ALTER TABLE gold.hourly_demand_summary ADD PRIMARY KEY (pickup_date, pickup_hour);

-- ------------------------------------------------------------------
-- gold.zone_performance_summary
--
-- Satu baris per zona taksi (termasuk zona dengan nol pickup via
-- LEFT JOIN). Merangkum jumlah pickup, revenue, dan rata-rata
-- fare/tip/jarak.
-- ------------------------------------------------------------------
CREATE TABLE gold.zone_performance_summary AS
SELECT
    z.location_id,
    z.borough,
    z.zone,
    COUNT(t.trip_id) AS total_pickup_trips,
    SUM(t.total_amount) AS total_revenue,
    AVG(t.fare_amount) AS avg_fare,
    AVG(t.tip_amount) AS avg_tip,
    AVG(t.trip_distance) AS avg_distance
FROM silver.taxi_zones z
LEFT JOIN silver.taxi_trips_cleaned t
    ON t.pickup_location_id = z.location_id
GROUP BY z.location_id, z.borough, z.zone;

ALTER TABLE gold.zone_performance_summary ADD PRIMARY KEY (location_id);

-- ------------------------------------------------------------------
-- gold.payment_behavior_summary
--
-- Satu baris per tipe pembayaran. Menampilkan jumlah trip, total
-- revenue, rata-rata tip, dan rasio tip rata-rata (tip / total_amount).
-- ------------------------------------------------------------------
CREATE TABLE gold.payment_behavior_summary AS
SELECT
    payment_type,
    payment_label,
    COUNT(*) AS total_trips,
    SUM(total_amount) AS total_revenue,
    AVG(total_amount) AS avg_revenue,
    AVG(tip_amount) AS avg_tip,
    AVG(CASE WHEN total_amount > 0 THEN tip_amount / total_amount ELSE 0 END) AS avg_tip_ratio
FROM silver.taxi_trips_cleaned
GROUP BY payment_type, payment_label;

ALTER TABLE gold.payment_behavior_summary ADD PRIMARY KEY (payment_type);

-- ------------------------------------------------------------------
-- gold.route_performance_summary
--
-- Satu baris per pasangan zone pickup → dropoff yang unik.
-- Menyertakan nama borough dan zona untuk kedua endpoint, plus
-- agregat jumlah trip, revenue, durasi, dan jarak.
-- ------------------------------------------------------------------
CREATE TABLE gold.route_performance_summary AS
SELECT
    pickup_location_id,
    pz.borough AS pickup_borough,
    pz.zone AS pickup_zone,
    dropoff_location_id,
    dz.borough AS dropoff_borough,
    dz.zone AS dropoff_zone,
    COUNT(*) AS total_trips,
    SUM(total_amount) AS total_revenue,
    AVG(trip_duration_minutes) AS avg_duration_minutes,
    AVG(trip_distance) AS avg_distance
FROM silver.taxi_trips_cleaned t
JOIN silver.taxi_zones pz ON pz.location_id = t.pickup_location_id
JOIN silver.taxi_zones dz ON dz.location_id = t.dropoff_location_id
GROUP BY pickup_location_id, pz.borough, pz.zone, dropoff_location_id, dz.borough, dz.zone;

ALTER TABLE gold.route_performance_summary ADD PRIMARY KEY (pickup_location_id, dropoff_location_id);
