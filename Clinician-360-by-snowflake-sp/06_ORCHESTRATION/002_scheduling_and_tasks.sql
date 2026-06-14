/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  06_ORCHESTRATION/002_scheduling_and_tasks.sql
  
  Purpose: Creates Snowflake Tasks for automated scheduling and 
           monitoring views for operational oversight.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA ORCHESTRATION;

-- ============================================================
-- SCHEDULED TASK: Daily Incremental Run
-- ============================================================
CREATE OR REPLACE TASK ORCHESTRATION.TSK_P360_DAILY_INCREMENTAL
    WAREHOUSE = COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 6 * * * America/New_York'
    COMMENT   = 'Daily incremental Provider 360 pipeline at 6 AM ET'
    ALLOW_OVERLAPPING_EXECUTION = FALSE
AS
    CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('INCREMENTAL');

-- ============================================================
-- SCHEDULED TASK: Weekly Full Refresh (Sunday)
-- ============================================================
CREATE OR REPLACE TASK ORCHESTRATION.TSK_P360_WEEKLY_FULL
    WAREHOUSE = COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 2 * * 0 America/New_York'
    COMMENT   = 'Weekly full refresh Provider 360 pipeline on Sunday 2 AM ET'
    ALLOW_OVERLAPPING_EXECUTION = FALSE
AS
    CALL P360_SP.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

-- ============================================================
-- MONITORING VIEW: Run History Dashboard
-- ============================================================
CREATE OR REPLACE VIEW ORCHESTRATION.VW_RUN_HISTORY AS
SELECT
    run_id,
    package_name,
    run_mode,
    environment,
    run_status,
    initiated_by,
    start_timestamp,
    end_timestamp,
    duration_seconds,
    ROUND(duration_seconds / 60.0, 1) AS duration_minutes,
    total_rows_read,
    total_rows_written,
    total_rows_rejected,
    total_steps,
    completed_steps,
    failed_step_id,
    error_message,
    resume_from_step_id
FROM P360_SP.AUDIT.PKG_RUN_LOG
ORDER BY start_timestamp DESC;

-- ============================================================
-- MONITORING VIEW: Step Performance
-- ============================================================
CREATE OR REPLACE VIEW ORCHESTRATION.VW_STEP_PERFORMANCE AS
SELECT
    s.run_id,
    r.run_mode,
    s.step_name,
    s.step_layer,
    s.step_status,
    s.attempt_number,
    s.start_timestamp,
    s.end_timestamp,
    s.duration_seconds,
    s.rows_read,
    s.rows_written,
    s.rows_rejected,
    s.reject_percentage,
    s.error_message,
    r.start_timestamp AS run_start
FROM P360_SP.AUDIT.STEP_RUN_LOG s
JOIN P360_SP.AUDIT.PKG_RUN_LOG r ON s.run_id = r.run_id
ORDER BY r.start_timestamp DESC, s.start_timestamp;

-- ============================================================
-- MONITORING VIEW: Data Quality Dashboard
-- ============================================================
CREATE OR REPLACE VIEW ORCHESTRATION.VW_DQ_DASHBOARD AS
SELECT
    d.run_id,
    r.run_mode,
    r.start_timestamp AS run_date,
    d.source_table,
    d.total_records,
    d.passed_records,
    d.rejected_records,
    d.reject_percentage,
    d.threshold_exceeded,
    d.threshold_value,
    d.evaluation_timestamp
FROM P360_SP.AUDIT.DQ_RUN_LOG d
JOIN P360_SP.AUDIT.PKG_RUN_LOG r ON d.run_id = r.run_id
ORDER BY d.evaluation_timestamp DESC;

-- ============================================================
-- MONITORING VIEW: Error Analysis
-- ============================================================
CREATE OR REPLACE VIEW ORCHESTRATION.VW_ERROR_ANALYSIS AS
SELECT
    e.run_id,
    e.step_name,
    e.error_code,
    e.error_state,
    e.error_message,
    e.severity,
    e.error_timestamp,
    r.run_mode,
    r.environment
FROM P360_SP.AUDIT.ERROR_LOG e
JOIN P360_SP.AUDIT.PKG_RUN_LOG r ON e.run_id = r.run_id
ORDER BY e.error_timestamp DESC;

-- ============================================================
-- MONITORING VIEW: Reject Analysis
-- ============================================================
CREATE OR REPLACE VIEW ORCHESTRATION.VW_REJECT_ANALYSIS AS
SELECT
    rs.run_id,
    r.start_timestamp AS run_date,
    rs.step_name,
    rs.source_table,
    rs.reject_reason,
    rs.reject_count,
    rs.first_rejected_at,
    rs.last_rejected_at
FROM P360_SP.REJECT.REJECT_SUMMARY rs
JOIN P360_SP.AUDIT.PKG_RUN_LOG r ON rs.run_id = r.run_id
ORDER BY r.start_timestamp DESC, rs.reject_count DESC;

-- ============================================================
-- NOTE: Tasks are created in SUSPENDED state.
-- To activate: ALTER TASK ORCHESTRATION.TSK_P360_DAILY_INCREMENTAL RESUME;
-- ============================================================
