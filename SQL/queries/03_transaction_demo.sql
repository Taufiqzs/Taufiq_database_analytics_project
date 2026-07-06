-- ==========================================================================
-- 03_transaction_demo.sql — Demonstrasi Transaksi & Rollback
--
-- Tujuan:
--   Mendemonstrasikan penggunaan transaksi database yang benar dengan
--   pola BEGIN/ROLLBACK. Skrip ini menyisipkan pipeline run uji coba,
--   menjalankan query, dan kemudian mengembalikan semuanya — tanpa
--   meninggalkan efek samping.
--
-- Ini berguna untuk:
--   - Menguji bahwa tabel audit dapat diakses.
--   - Memverifikasi sintaks query terhadap tabel silver/gold.
--   - Mendemonstrasikan analisis eksplorasi yang aman dengan rollback.
-- ==========================================================================

BEGIN;

-- Insert a dummy pipeline run to test audit logging.
INSERT INTO audit.pipeline_run (run_name, status, message)
VALUES ('transaction_demo', 'STARTED', 'Manual transaction demo')
RETURNING run_id;

-- Example read-only query: count clean trips.
SELECT COUNT(*) AS current_valid_trips
FROM silver.taxi_trips_cleaned;

-- Roll back the transaction so the dummy run is never persisted.
ROLLBACK;

