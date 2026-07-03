-- ==========================================================================
-- 06_functions_procedures.sql — Audit Logging Functions & Procedures
--
-- Purpose:
--   Provides reusable PL/pgSQL routines for recording pipeline execution
--   steps in the audit schema.
--
-- Objects:
--   FUNCTION  audit.log_pipeline_step(...)  – Insert a single load-audit row.
--   PROCEDURE audit.finish_pipeline_run(...) – Mark a pipeline run as finished.
-- ==========================================================================

-- ------------------------------------------------------------------
-- audit.log_pipeline_step (FUNCTION)
--
-- Inserts a row into audit.load_audit recording a single processing
-- step within a pipeline run.
--
-- Parameters:
--   p_run_id      – FK referencing audit.pipeline_run.
--   p_layer_name  – The data layer (e.g. 'bronze', 'silver', 'gold').
--   p_object_name – The table or object being processed.
--   p_row_count   – Number of rows affected / loaded.
--   p_status      – 'SUCCESS' or 'FAILED'.
--   p_message     – Optional additional context or error message.
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
-- Updates the corresponding audit.pipeline_run row with the final
-- status, a finish timestamp, and an optional message.
--
-- Parameters:
--   p_run_id  – The run to finalise.
--   p_status  – Final status ('SUCCESS' or 'FAILED').
--   p_message – Optional summary or error description.
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

