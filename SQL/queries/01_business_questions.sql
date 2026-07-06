-- ==========================================================================
-- 01_business_questions.sql — Query Bisnis Utama
--
-- Tujuan:
--   Menjawab pertanyaan bisnis fundamental tentang operasi taksi NYC
--   pada Januari 2026. Setiap query menargetkan tabel silver (bersih)
--   atau gold (teragregasi).
-- ==========================================================================

-- ------------------------------------------------------------------
-- Q1: Jumlah total trip yang tervalidasi (bersih)
-- ------------------------------------------------------------------
-- 1. Jumlah total trip valid pada Januari 2026
SELECT COUNT(*) AS jumlah_total_trip_valid
FROM silver.taxi_trips_cleaned;

-- ------------------------------------------------------------------
-- Q2: Total revenue, rata-rata revenue, rata-rata fare, dan rata-rata tip
-- ------------------------------------------------------------------
-- 2. Total revenue, average revenue, average fare, dan average tip
-- SELECT
--     SUM(total_amount) AS total_revenue,
--     AVG(total_amount) AS avg_revenue,
--     AVG(fare_amount) AS avg_fare,
--     AVG(tip_amount) AS avg_tip
-- FROM silver.taxi_trips_cleaned;

SELECT
    '$' || TO_CHAR(SUM(total_amount), 'FM999G999G999G999G990D00') AS total_revenue,
    '$' || TO_CHAR(AVG(total_amount), 'FM999G999G999G999G990D00') AS avg_revenue,
    '$' || TO_CHAR(AVG(fare_amount), 'FM999G999G999G999G990D00') AS avg_fare,
    '$' || TO_CHAR(AVG(tip_amount), 'FM999G999G999G999G990D00') AS avg_tip
FROM silver.taxi_trips_cleaned;

-- ------------------------------------------------------------------
-- Q3: 10 kombinasi tanggal-jam teratas berdasarkan volume trip
-- ------------------------------------------------------------------
-- 3. Tanggal dan jam dengan jumlah trip tertinggi
SELECT pickup_date, pickup_hour, total_trips
FROM gold.hourly_demand_summary
ORDER BY total_trips DESC
LIMIT 10;

-- ------------------------------------------------------------------
-- Q4: Jumlah trip berdasarkan weekday vs. weekend
-- ------------------------------------------------------------------
-- 4. Perbandingan jumlah trip weekday dan weekend
SELECT
    CASE WHEN is_weekend THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    COUNT(*) AS total_trips,
    SUM(total_amount) AS total_revenue
FROM silver.taxi_trips_cleaned
GROUP BY day_type
ORDER BY total_trips DESC;

-- ------------------------------------------------------------------
-- Q5: Metode pembayaran yang paling sering digunakan
-- ------------------------------------------------------------------
-- 5. Payment type paling sering digunakan
SELECT payment_label, total_trips, total_revenue
FROM gold.payment_behavior_summary
ORDER BY total_trips DESC;

-- ------------------------------------------------------------------
-- Q6-7: 10 zona teratas berdasarkan jumlah pickup dan berdasarkan revenue
-- ------------------------------------------------------------------
-- 6. Borough atau zone pickup dengan jumlah trip tertinggi
SELECT borough, zone, total_pickup_trips
FROM gold.zone_performance_summary
ORDER BY total_pickup_trips DESC
LIMIT 10;

-- 7. Zone pickup yang menghasilkan total revenue tertinggi
SELECT borough, zone, total_revenue
FROM gold.zone_performance_summary
ORDER BY total_revenue DESC NULLS LAST
LIMIT 10;

-- SELECT
--     borough,
--     zone,
--     '$' || TO_CHAR(total_revenue, 'FM999G999G999G999G990D00') AS total_revenue
-- FROM (
--     SELECT
--         borough,
--         zone,
--         total_revenue
--     FROM gold.zone_performance_summary
--     ORDER BY total_revenue DESC NULLS LAST
--     LIMIT 10
-- ) ranked_zones;
-- ------------------------------------------------------------------
-- Q8: Rute pickup → dropoff yang paling sering terjadi
-- ------------------------------------------------------------------
-- 8. Rute pickup ke dropoff yang paling sering terjadi
SELECT pickup_borough, pickup_zone, dropoff_borough, dropoff_zone, total_trips
FROM gold.route_performance_summary
ORDER BY total_trips DESC
LIMIT 10;

-- ------------------------------------------------------------------
-- Q9: Analisis waktu (Morning / Afternoon / Evening / Night)
-- ------------------------------------------------------------------
-- 9. Trip, revenue, dan average duration per time period
SELECT
    time_period,
    COUNT(*) AS total_trips,
    SUM(total_amount) AS total_revenue,
    AVG(trip_duration_minutes) AS avg_duration_minutes
FROM silver.taxi_trips_cleaned
GROUP BY time_period
ORDER BY total_trips DESC;

-- ------------------------------------------------------------------
-- Q10: Masalah kualitas data yang paling umum
-- ------------------------------------------------------------------
-- 10. Data quality issue terbanyak berdasarkan error_type
SELECT error_type, COUNT(*) AS issue_count
FROM silver.data_quality_issues
GROUP BY error_type
ORDER BY issue_count DESC;

-- ------------------------------------------------------------------
-- Q11: Deteksi anomali pada jumlah trip per jam
--
-- Mengidentifikasi jam di mana total_trips menyimpang lebih dari 2
-- standar deviasi dari rata-rata, menandakan potensi outlier atau
-- masalah kualitas data.
-- ------------------------------------------------------------------
-- 11. Tanggal atau jam dengan pola trip count tidak wajar
WITH hourly_stats AS (
    SELECT pickup_date, pickup_hour, total_trips
    FROM gold.hourly_demand_summary
),
baseline AS (
    SELECT AVG(total_trips) AS avg_trips, STDDEV_POP(total_trips) AS stddev_trips
    FROM hourly_stats
)
SELECT h.*
FROM hourly_stats h
CROSS JOIN baseline b
WHERE h.total_trips > b.avg_trips + (2 * b.stddev_trips)
   OR h.total_trips < GREATEST(b.avg_trips - (2 * b.stddev_trips), 0)
ORDER BY h.total_trips DESC;


-- ------------------------------------------------------------------
-- Q13: 10 zona pickup teratas berdasarkan total revenue
-- ------------------------------------------------------------------
-- 13. Top 10 pickup zone berdasarkan revenue
WITH zone_revenue AS (
    SELECT borough, zone, total_revenue
    FROM gold.zone_performance_summary
)
SELECT *
FROM zone_revenue
ORDER BY total_revenue DESC NULLS LAST
LIMIT 10;

-- ------------------------------------------------------------------
-- Q14: Zona dengan volume tinggi tetapi rata-rata tip rendah
--
-- Menggunakan PERCENT_RANK untuk mencari zona di 75% teratas untuk
-- volume pickup tetapi 25% terbawah untuk rata-rata tip — potensi
-- indikator kualitas layanan.
-- ------------------------------------------------------------------
-- 14. Zone dengan pickup tinggi tetapi average tip rendah
WITH zone_metrics AS (
    SELECT
        borough,
        zone,
        total_pickup_trips,
        avg_tip,
        PERCENT_RANK() OVER (ORDER BY total_pickup_trips) AS pickup_percentile,
        PERCENT_RANK() OVER (ORDER BY avg_tip) AS tip_percentile
    FROM gold.zone_performance_summary
    WHERE total_pickup_trips > 0
)
SELECT *
FROM zone_metrics
WHERE pickup_percentile >= 0.75
  AND tip_percentile <= 0.25
ORDER BY total_pickup_trips DESC;

-- ------------------------------------------------------------------
-- Q15: Bandingkan revenue setiap hari dengan rata-rata harian
-- ------------------------------------------------------------------
-- 15. Perbandingan revenue setiap hari terhadap rata-rata revenue harian
SELECT
    pickup_date,
    total_revenue,
    AVG(total_revenue) OVER () AS avg_daily_revenue,
    total_revenue - AVG(total_revenue) OVER () AS revenue_vs_average
FROM gold.daily_trip_summary
ORDER BY pickup_date;

-- ------------------------------------------------------------------
-- Q16: Trip dengan durasi melebihi rata-rata untuk zona pickupnya
--
-- Menggunakan AVG() sebagai window function yang dipartisi oleh
-- pickup_location_id, kemudian memfilter trip yang lebih panjang
-- dari rata-rata zona tersebut.
-- ------------------------------------------------------------------
-- 16. Trip dengan durasi di atas rata-rata durasi untuk zone yang sama
WITH zone_duration AS (
    SELECT
        t.*,
        AVG(trip_duration_minutes) OVER (PARTITION BY pickup_location_id) AS avg_zone_duration
    FROM gold.vw_trip_enriched t
)
SELECT
    trip_id,
    pickup_datetime,
    pickup_borough,
    pickup_zone,
    trip_duration_minutes,
    avg_zone_duration
FROM zone_duration
WHERE trip_duration_minutes > avg_zone_duration
ORDER BY trip_duration_minutes DESC
LIMIT 100;

-- ------------------------------------------------------------------
-- Q17: Identifikasi borough dengan pangsa revenue < 5%
-- ------------------------------------------------------------------
-- 17. Pickup borough dengan kontribusi revenue tidak signifikan dibanding borough lain
WITH borough_revenue AS (
    SELECT
        pickup_borough,
        SUM(total_amount) AS total_revenue
    FROM gold.vw_trip_enriched
    GROUP BY pickup_borough
),
share_calc AS (
    SELECT
        pickup_borough,
        total_revenue,
        total_revenue / SUM(total_revenue) OVER () AS revenue_share
    FROM borough_revenue
)
SELECT *
FROM share_calc
WHERE revenue_share < 0.05
ORDER BY revenue_share;

-- ------------------------------------------------------------------
-- Q18: Peringkat semua zona pickup berdasarkan total revenue
-- ------------------------------------------------------------------
-- 18. Ranking pickup zone berdasarkan total revenue
SELECT
    borough,
    zone,
    total_revenue,
    RANK() OVER (ORDER BY total_revenue DESC NULLS LAST) AS revenue_rank
FROM gold.zone_performance_summary;

-- ------------------------------------------------------------------
-- Q19:
--
-- Menggunakan ROW_NUMBER() yang dipartisi oleh borough untuk
-- memberi peringkat zona per borough.
-- ------------------------------------------------------------------
-- 19  
WITH ranked_zone AS (
    SELECT
        borough,
        zone,
        total_revenue,
        total_pickup_trips,
        ROW_NUMBER() OVER (
            PARTITION BY borough
            ORDER BY total_revenue DESC NULLS LAST
        ) AS borough_rank
    FROM gold.zone_performance_summary
)
SELECT *
FROM ranked_zone
WHERE borough_rank <= 3
ORDER BY borough, borough_rank;

-- ------------------------------------------------------------------
-- Q20: Total revenue berjalan (kumulatif) antar tanggal
-- ------------------------------------------------------------------
-- 20. Running total revenue per tanggal
SELECT
    pickup_date,
    total_revenue,
    SUM(total_revenue) OVER (ORDER BY pickup_date) AS running_total_revenue
FROM gold.daily_trip_summary
ORDER BY pickup_date;

-- ------------------------------------------------------------------
-- Q21: Rata-rata bergerak 7 hari dari jumlah trip harian
-- ------------------------------------------------------------------
-- 21. Moving average trip count 7 hari
SELECT
    pickup_date,
    total_trips,
    AVG(total_trips) OVER (
        ORDER BY pickup_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS moving_avg_trip_7d
FROM gold.daily_trip_summary
ORDER BY pickup_date;

-- ------------------------------------------------------------------
-- Q22: Perubahan revenue hari-ke-hari menggunakan LAG
-- ------------------------------------------------------------------
-- 22. Revenue hari ini dibanding hari sebelumnya menggunakan LAG
SELECT
    pickup_date,
    total_revenue,
    LAG(total_revenue) OVER (ORDER BY pickup_date) AS previous_day_revenue,
    total_revenue - LAG(total_revenue) OVER (ORDER BY pickup_date) AS revenue_delta
FROM gold.daily_trip_summary
ORDER BY pickup_date;

-- ------------------------------------------------------------------
-- Q23: Ambil top 3 pickup zone untuk setiap borough menggunakan
-- ROW_NUMBER, RANK, atau DENSE_RANK.
-- ------------------------------------------------------------------
-- 23. Ambil top 3 pickup zone untuk setiap borough menggunakan ROW_NUMBER, RANK, atau DENSE_RANK.
WITH ranked_zones AS (
    SELECT
        borough,
        zone,
        total_pickup_trips,
        total_revenue,
        ROW_NUMBER() OVER (
            PARTITION BY borough
            ORDER BY total_pickup_trips DESC, total_revenue DESC
        ) AS zone_rank
    FROM gold.zone_performance_summary
    WHERE total_pickup_trips > 0
)
SELECT
    borough,
    zone,
    total_pickup_trips,
    total_revenue,
    zone_rank
FROM ranked_zones
WHERE zone_rank <= 3
ORDER BY borough, zone_rank;


