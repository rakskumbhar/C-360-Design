-- SCD Type-2 hash-diff tracking for provider attributes in SILVER schema
-- Co-authored with CoCo
/*=============================================================================
  03_SILVER/003_sp_scd2_provider_attributes.sql
=============================================================================*/

USE DATABASE P360_DQ;
USE SCHEMA SILVER;

CREATE OR REPLACE PROCEDURE SILVER.SP_SCD2_PROVIDER_ATTRIBUTES(
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
    v_new_count NUMBER DEFAULT 0;
    v_changed_count NUMBER DEFAULT 0;
    v_err_msg VARCHAR;
BEGIN
    v_step_run_id := UUID_STRING();
    CALL P360_DQ.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 40, 'SCD2_PROVIDER_ATTRIBUTES', 'SILVER', 1);

    CREATE OR REPLACE TEMPORARY TABLE _tmp_scd2_source AS
    SELECT
        PROVIDER_BK, PROVIDER_NAME, CREDENTIAL, STATE, ZIP_CODE,
        PRIMARY_SPECIALTY, ROW_STATUS AS PROVIDER_STATUS,
        MD5(COALESCE(PROVIDER_NAME,'') || '|' || COALESCE(CREDENTIAL,'') || '|' ||
            COALESCE(STATE,'') || '|' || COALESCE(ZIP_CODE,'') || '|' ||
            COALESCE(PRIMARY_SPECIALTY,'') || '|' || COALESCE(ROW_STATUS,'')) AS _HASH_DIFF
    FROM P360_DQ.SILVER.DIM_PROVIDER
    WHERE DQ_STATUS IN ('PASS', 'PASS-SOFT');

    SELECT COUNT(*) INTO v_total_count FROM _tmp_scd2_source;

    -- Close changed versions
    UPDATE P360_DQ.SILVER.SCD2_PROVIDER_ATTRIBUTES tgt
    SET _VALID_TO = CURRENT_TIMESTAMP(), _IS_CURRENT = FALSE
    WHERE tgt._IS_CURRENT = TRUE
      AND EXISTS (SELECT 1 FROM _tmp_scd2_source src WHERE src.PROVIDER_BK = tgt.PROVIDER_BK AND src._HASH_DIFF != tgt._HASH_DIFF);
    v_changed_count := SQLROWCOUNT;

    -- Insert new/changed versions
    INSERT INTO P360_DQ.SILVER.SCD2_PROVIDER_ATTRIBUTES (
        SCD_KEY, PROVIDER_BK, PROVIDER_NAME, CREDENTIAL, STATE, ZIP_CODE,
        PRIMARY_SPECIALTY, PROVIDER_STATUS, _VALID_FROM, _VALID_TO, _IS_CURRENT, _HASH_DIFF, _RUN_ID
    )
    SELECT
        MD5(src.PROVIDER_BK || '|' || CAST(CURRENT_TIMESTAMP() AS VARCHAR)),
        src.PROVIDER_BK, src.PROVIDER_NAME, src.CREDENTIAL, src.STATE, src.ZIP_CODE,
        src.PRIMARY_SPECIALTY, src.PROVIDER_STATUS,
        CURRENT_TIMESTAMP(), '9999-12-31'::TIMESTAMP_NTZ, TRUE, src._HASH_DIFF, :P_RUN_ID
    FROM _tmp_scd2_source src
    WHERE NOT EXISTS (
        SELECT 1 FROM P360_DQ.SILVER.SCD2_PROVIDER_ATTRIBUTES tgt
        WHERE tgt.PROVIDER_BK = src.PROVIDER_BK AND tgt._IS_CURRENT = TRUE AND tgt._HASH_DIFF = src._HASH_DIFF
    );
    v_new_count := SQLROWCOUNT;

    DROP TABLE IF EXISTS _tmp_scd2_source;
    CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_total_count, :v_new_count, 0, :v_changed_count, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', :v_total_count, 'new_versions', :v_new_count, 'closed_versions', :v_changed_count);
EXCEPTION
    WHEN OTHER THEN
        DROP TABLE IF EXISTS _tmp_scd2_source;
        LET v_err_msg := SQLERRM;
        CALL P360_DQ.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'SCD2_PROVIDER_ATTRIBUTES', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
