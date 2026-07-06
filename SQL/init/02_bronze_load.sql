-- ==========================================================================
-- 02_bronze_load.sql — Pembersihan Layer Bronze
--
-- Tujuan:
--   Memotong (truncate) tabel staging bronze sebelum pemuatan massal
--   berbasis Python.
--
-- Catatan:
--   - Pemuatan data aktual dilakukan oleh `scripts/load_to_postgres.py`
--     menggunakan pandas `to_sql`.
--   - Skrip ini memastikan tabel bronze kosong dan siap menerima data
--     baru, membuat pipeline idempoten (aman untuk dijalankan ulang).
-- ==========================================================================

TRUNCATE TABLE bronze.raw_taxi_trips;
TRUNCATE TABLE bronze.raw_taxi_zones;

