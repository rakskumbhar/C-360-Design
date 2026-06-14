/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  03_SILVER/003_sp_int_network_affiliations.sql
  
  Purpose: Enriches network affiliations with participation status derivation.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA SILVER;

CREATE OR REPLACE PROCEDURE SILVER.SP_INT_NETWORK_AFFILIATIONS(
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
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 12, 'INT_NETWORK_AFFILIATIONS', 'SILVER', 1);

    IF (:P_MODE = 'INCREMENTAL') THEN
        SELECT COALESCE(MAX(_source_loaded_at), '1900-01-01'::TIMESTAMP_NTZ) INTO v_hwm
        FROM P360_SP.SILVER.INT_NETWORK_AFFILIATIONS;
    ELSE
        v_hwm := '1900-01-01'::TIMESTAMP_NTZ;
        TRUNCATE TABLE P360_SP.SILVER.INT_NETWORK_AFFILIATIONS;
    END IF;

    CREATE OR REPLACE TEMPORARY TABLE _tmp_network AS
    SELECT
        MD5(COALESCE(CAST(network_affiliation_id AS VARCHAR), '_null_')) AS affiliation_sk,
        network_affiliation_id,
        npi_number,
        network_name,
        network_tier,
        participation_status,
        effective_date,
        termination_date,
        par_agreement_type,
        CASE
            WHEN participation_status = 'PARTICIPATING'
                 AND (termination_date IS NULL OR termination_date > CURRENT_DATE())
            THEN TRUE
            ELSE FALSE
        END AS is_currently_participating,
        _source_loaded_at,
        CURRENT_TIMESTAMP() AS _enriched_at,
        :P_RUN_ID AS _run_id
    FROM P360_SP.BRONZE.STG_NETWORK_AFFILIATIONS
    WHERE _source_loaded_at > :v_hwm;

    SELECT COUNT(*) INTO v_total_count FROM _tmp_network;

    IF (v_total_count = 0) THEN
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', 0, 0, 0, 0, NULL, NULL, NULL);
        RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', 0, 'rows_written', 0);
    END IF;

    MERGE INTO P360_SP.SILVER.INT_NETWORK_AFFILIATIONS tgt
    USING _tmp_network src
    ON tgt.affiliation_sk = src.affiliation_sk
    WHEN MATCHED THEN UPDATE SET
        network_affiliation_id = src.network_affiliation_id,
        npi_number = src.npi_number,
        network_name = src.network_name,
        network_tier = src.network_tier,
        participation_status = src.participation_status,
        effective_date = src.effective_date,
        termination_date = src.termination_date,
        par_agreement_type = src.par_agreement_type,
        is_currently_participating = src.is_currently_participating,
        _source_loaded_at = src._source_loaded_at,
        _enriched_at = src._enriched_at,
        _run_id = src._run_id
    WHEN NOT MATCHED THEN INSERT (
        affiliation_sk, network_affiliation_id, npi_number, network_name,
        network_tier, participation_status, effective_date, termination_date,
        par_agreement_type, is_currently_participating, _source_loaded_at, _enriched_at, _run_id
    ) VALUES (
        src.affiliation_sk, src.network_affiliation_id, src.npi_number, src.network_name,
        src.network_tier, src.participation_status, src.effective_date, src.termination_date,
        src.par_agreement_type, src.is_currently_participating, src._source_loaded_at, src._enriched_at, src._run_id
    );

    v_insert_count := SQLROWCOUNT;
    DROP TABLE IF EXISTS _tmp_network;

    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_total_count, :v_insert_count, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', :v_total_count, 'rows_written', :v_insert_count);

EXCEPTION
    WHEN OTHER THEN
        DROP TABLE IF EXISTS _tmp_network;
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'INT_NETWORK_AFFILIATIONS', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
