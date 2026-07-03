-- ==========================================================================
-- 05_views.sql — Gold Layer Convenience Views
--
-- Purpose:
--   Creates SQL views on top of silver and gold tables to provide
--   user-friendly abstractions for reporting and ad-hoc analysis.
--
-- Views:
--   gold.vw_trip_enriched       – Every cleaned trip with zone names.
--   gold.vw_daily_trip_summary  – Alias for gold.daily_trip_summary.
--   gold.vw_zone_performance    – Zone summary with dropoff counts added.
-- ==========================================================================

-- ------------------------------------------------------------------
-- gold.vw_trip_enriched
--
-- Joins every cleaned trip with pickup and dropoff zone details
-- (borough, zone name, service_zone). This is the denormalised,
-- analyst-friendly view of the trip data.
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
-- Simple passthrough view over gold.daily_trip_summary.
-- Useful for tools / ORMs that prefer views over tables.
-- ------------------------------------------------------------------
CREATE OR REPLACE VIEW gold.vw_daily_trip_summary AS
SELECT *
FROM gold.daily_trip_summary;

-- ------------------------------------------------------------------
-- gold.vw_zone_performance
--
-- Extends gold.zone_performance_summary with a total_dropoff_trips
-- column computed from silver.taxi_trips_cleaned, giving a more
-- complete picture of each zone's activity (both arrivals and departures).
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

