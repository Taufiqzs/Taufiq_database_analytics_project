-- ==========================================================================
-- 04_gold_mart.sql — Gold Layer Aggregated Marts
--
-- Purpose:
--   Builds the gold (presentation) layer by creating materialised summary
--   tables from the cleaned silver data. These tables are optimised for
--   dashboarding and ad-hoc analytical queries.
--
-- Tables created:
--   gold.daily_trip_summary        – Per-day trip counts, revenue, averages.
--   gold.hourly_demand_summary     – Per-hour demand & revenue breakdown.
--   gold.zone_performance_summary  – Per-zone pickup metrics.
--   gold.payment_behavior_summary  – Payment method analysis (tip ratios).
--   gold.route_performance_summary – Pickup → dropoff route statistics.
--
-- Idempotent: Drops any existing gold tables/views first, then recreates.
-- ==========================================================================

-- ------------------------------------------------------------------
-- Step 0: Drop existing objects (clean slate for idempotent re-run)
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
-- One row per calendar day in the dataset.
-- Provides daily totals and averages for revenue, fare, tip, distance,
-- and trip duration.
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
-- One row per date + hour combination. Includes a time_period label
-- (Morning / Afternoon / Evening / Night) for convenient grouping.
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
-- One row per taxi zone (including zones with zero pickups via LEFT JOIN).
-- Summarises pickup counts, revenue, and average fare/tip/distance.
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
-- One row per payment type. Shows trip count, total revenue, average
-- tip, and the average tip ratio (tip / total_amount).
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
-- One row per unique pickup → dropoff zone pair.
-- Includes borough and zone names for both endpoints, plus aggregate
-- trip counts, revenue, duration, and distance.
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
