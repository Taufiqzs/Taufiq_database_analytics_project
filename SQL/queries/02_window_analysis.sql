-- ==========================================================================
-- 02_window_analysis.sql — Analisis Window Function Lanjutan
--
-- Tujuan:
--   Mendemonstrasikan penggunaan window function PostgreSQL (RANK,
--   ROW_NUMBER, PERCENT_RANK, LAG, AVG OVER, SUM OVER) untuk menjawab
--   pertanyaan analitis yang lebih canggih tentang data taksi NYC.
--
-- Pertanyaan yang dijawab:
--   13. 10 zona pickup teratas berdasarkan revenue.
--   14. Zona dengan pickup tinggi tetapi rata-rata tip rendah.
--   15. Perbandingan revenue harian vs. rata-rata keseluruhan.
--   16. Trip lebih panjang dari rata-rata untuk zona pickupnya.
--   17. Borough dengan pangsa revenue tidak signifikan (< 5%).
--   18. Peringkat lengkap zona berdasarkan revenue.
--   19 & 23. 3 zona teratas per borough.
--   20. Total revenue berjalan (kumulatif) dari waktu ke waktu.
--   21. Rata-rata bergerak 7 hari dari jumlah trip.
--   22. Delta revenue hari-ke-hari menggunakan LAG.
-- ==========================================================================

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
-- Q19 & Q23: 3 zona dengan performa terbaik di setiap borough
--
-- Menggunakan ROW_NUMBER() yang dipartisi oleh borough untuk
-- memberi peringkat zona per borough.
-- ------------------------------------------------------------------
-- 19 dan 23. Top 3 pickup zone untuk setiap borough
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

