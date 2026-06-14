/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  04_GOLD/003_sp_fct_provider_visits.sql
  
  Purpose: Builds provider visits fact table with derived payment columns.
           Supports incremental merge processing.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA GOLD;

CREATE OR REPLACE PROCEDURE GOLD.SP_FCT_PROVIDER_VISITS(
    P_RUN_ID    VARCHAR,
    P_MODE      VARCHAR DEFAULT 'INCREMENTAL'
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
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 32, 'FCT_PROVIDER_VISITS', 'GOLD', 1);

    IF (:P_MODE = 'INCREMENTAL') THEN
        SELECT COALESCE(MAX(_source_loaded_at), '1900-01-01'::TIMESTAMP_NTZ) INTO v_hwm
        FROM P360_SP.GOLD.FCT_PROVIDER_VISITS;
    ELSE
        v_hwm := '1900-01-01'::TIMESTAMP_NTZ;
        TRUNCATE TABLE P360_SP.GOLD.FCT_PROVIDER_VISITS;
    END IF;

    CREATE OR REPLACE TEMPORARY TABLE _tmp_visits AS
    SELECT
        MD5(COALESCE(CAST(claim_id AS VARCHAR), '_null_')) AS visit_sk,
        claim_id,
        npi_number,
        patient_id,
        service_date,
        procedure_code,
        diagnosis_code,
        allowed_amount,
        paid_amount,
        claim_status,
        network_status,
        CASE WHEN claim_status = 'PAID' THEN paid_amount ELSE 0 END AS net_paid_amount,
        CASE WHEN claim_status = 'PAID' THEN allowed_amount - paid_amount ELSE 0 END AS patient_responsibility,
        _source_loaded_at,
        CURRENT_TIMESTAMP() AS _loaded_at,
        :P_RUN_ID AS _run_id
    FROM P360_SP.BRONZE.STG_CLAIMS_PROVIDERS
    WHERE _source_loaded_at > :v_hwm;

    SELECT COUNT(*) INTO v_total_count FROM _tmp_visits;

    IF (v_total_count = 0) THEN
        DROP TABLE IF EXISTS _tmp_visits;
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', 0, 0, 0, 0, NULL, NULL, NULL);
        RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', 0, 'rows_written', 0);
    END IF;

    MERGE INTO P360_SP.GOLD.FCT_PROVIDER_VISITS tgt
    USING _tmp_visits src
    ON tgt.visit_sk = src.visit_sk
    WHEN MATCHED THEN UPDATE SET
        claim_id = src.claim_id, npi_number = src.npi_number, patient_id = src.patient_id,
        service_date = src.service_date, procedure_code = src.procedure_code,
        diagnosis_code = src.diagnosis_code, allowed_amount = src.allowed_amount,
        paid_amount = src.paid_amount, claim_status = src.claim_status,
        network_status = src.network_status, net_paid_amount = src.net_paid_amount,
        patient_responsibility = src.patient_responsibility,
        _source_loaded_at = src._source_loaded_at, _loaded_at = src._loaded_at, _run_id = src._run_id
    WHEN NOT MATCHED THEN INSERT (
        visit_sk, claim_id, npi_number, patient_id, service_date, procedure_code,
        diagnosis_code, allowed_amount, paid_amount, claim_status, network_status,
        net_paid_amount, patient_responsibility, _source_loaded_at, _loaded_at, _run_id
    ) VALUES (
        src.visit_sk, src.claim_id, src.npi_number, src.patient_id, src.service_date, src.procedure_code,
        src.diagnosis_code, src.allowed_amount, src.paid_amount, src.claim_status, src.network_status,
        src.net_paid_amount, src.patient_responsibility, src._source_loaded_at, src._loaded_at, src._run_id
    );

    v_insert_count := SQLROWCOUNT;
    DROP TABLE IF EXISTS _tmp_visits;

    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_total_count, :v_insert_count, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', :v_total_count, 'rows_written', :v_insert_count);

EXCEPTION
    WHEN OTHER THEN
        DROP TABLE IF EXISTS _tmp_visits;
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'FCT_PROVIDER_VISITS', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
