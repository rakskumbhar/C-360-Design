-- Stages Specialty Type data from RAW to Bronze with no inline reject filtering
/*=============================================================================
  02_BRONZE/002_sp_stg_specialty_type.sql
=============================================================================*/

USE DATABASE P360_DQ;
USE SCHEMA BRONZE;

CREATE OR REPLACE PROCEDURE BRONZE.SP_STG_SPECIALTY_TYPE(
    P_RUN_ID VARCHAR, P_MODE VARCHAR DEFAULT 'INCREMENTAL'
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_step_run_id VARCHAR;
    v_total_count NUMBER DEFAULT 0;
    v_insert_count NUMBER DEFAULT 0;
    v_hwm TIMESTAMP_NTZ;
    v_err_msg VARCHAR;
BEGIN
    v_step_run_id := UUID_STRING();
    CALL P360_DQ.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 2, 'STG_SPECIALTY_TYPE', 'BRONZE', 1);

    IF (:P_MODE = 'FULL') THEN
        v_hwm := '1900-01-01'::TIMESTAMP_NTZ;
        TRUNCATE TABLE P360_DQ.BRONZE.STG_SPECIALTY_TYPE;
    ELSE
        SELECT COALESCE(MAX(_SOURCE_LOADED_AT), '1900-01-01'::TIMESTAMP_NTZ) INTO v_hwm
        FROM P360_DQ.BRONZE.STG_SPECIALTY_TYPE;
    END IF;

    SELECT COUNT(*) INTO v_total_count
    FROM P360_DQ.RAW_INGESTION.RAW_SPECIALTY_TYPE WHERE _LOADED_AT > :v_hwm;

    IF (:v_total_count = 0) THEN
        CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', 0, 0, 0, 0, NULL, NULL, NULL);
        RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', 0, 'rows_written', 0);
    END IF;

    INSERT INTO P360_DQ.BRONZE.STG_SPECIALTY_TYPE (
        SPECIALTY_CODE, SPECIALTY_NAME, SPECIALTY_CATEGORY, BOARD_CERTIFICATION_REQ,
        STATE, EFFECTIVE_DATE, EXPIRATION_DATE, SOURCE_SYSTEM,
        LOAD_DT, DQ_STATUS, RECORD_HASH, JOB_ID, _SOURCE_LOADED_AT, _RUN_ID
    )
    SELECT
        SPECIALTY_CODE, SPECIALTY_NAME, SPECIALTY_CATEGORY, BOARD_CERTIFICATION_REQ,
        STATE, EFFECTIVE_DATE, EXPIRATION_DATE, SOURCE_SYSTEM,
        CURRENT_TIMESTAMP(), NULL,
        MD5(COALESCE(SPECIALTY_CODE,'') || '|' || COALESCE(SPECIALTY_NAME,'') || '|' || COALESCE(STATE,'')),
        :P_RUN_ID, _LOADED_AT, :P_RUN_ID
    FROM P360_DQ.RAW_INGESTION.RAW_SPECIALTY_TYPE WHERE _LOADED_AT > :v_hwm;

    v_insert_count := SQLROWCOUNT;
    CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_total_count, :v_insert_count, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', :v_total_count, 'rows_written', :v_insert_count);
EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_DQ.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'STG_SPECIALTY_TYPE', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
