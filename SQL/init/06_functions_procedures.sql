-- ==========================================================================
-- 06_functions_procedures.sql — Fungsi & Prosedur Audit Logging
--
-- Tujuan:
--   Menyediakan rutin PL/pgSQL yang dapat digunakan kembali untuk
--   merekam langkah eksekusi pipeline di skema audit.
--
-- Objek:
--   FUNCTION  audit.log_pipeline_step(...)  – Menyisipkan satu baris
--     load-audit.
--   PROCEDURE audit.finish_pipeline_run(...) – Menandai pipeline run
--     sebagai selesai.
-- ==========================================================================

-- ------------------------------------------------------------------
-- audit.log_pipeline_step (FUNCTION)
--
-- Menyisipkan baris ke audit.load_audit yang mencatat satu langkah
-- pemrosesan dalam pipeline run.
--
-- Parameter:
--   p_run_id      – FK yang merujuk ke audit.pipeline_run.
--   p_layer_name  – Layer data (mis. 'bronze', 'silver', 'gold').
--   p_object_name – Tabel atau objek yang diproses.
--   p_row_count   – Jumlah baris yang terpengaruh / dimuat.
--   p_status      – 'SUCCESS' atau 'FAILED'.
--   p_message     – Konteks tambahan atau pesan error opsional.
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit.log_pipeline_step(
    p_run_id BIGINT,
    p_layer_name TEXT,
    p_object_name TEXT,
    p_row_count BIGINT,
    p_status TEXT,
    p_message TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    INSERT INTO audit.load_audit (
        run_id,
        layer_name,
        object_name,
        row_count,
        status,
        message
    )
    VALUES (
        p_run_id,
        p_layer_name,
        p_object_name,
        p_row_count,
        p_status,
        p_message
    );
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------------
-- audit.finish_pipeline_run (PROCEDURE)
--
-- Memperbarui baris audit.pipeline_run yang sesuai dengan status
-- akhir, timestamp selesai, dan pesan opsional.
--
-- Parameter:
--   p_run_id  – Run yang akan diselesaikan.
--   p_status  – Status akhir ('SUCCESS' atau 'FAILED').
--   p_message – Ringkasan atau deskripsi error opsional.
-- ------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE audit.finish_pipeline_run(
    p_run_id BIGINT,
    p_status TEXT,
    p_message TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE audit.pipeline_run
    SET status = p_status,
        finished_at = NOW(),
        message = p_message
    WHERE run_id = p_run_id;
END;
$$;

