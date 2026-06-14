/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  04_GOLD/002_sp_dim_provider_network.sql
  
  Purpose: Builds provider network dimension with tenure calculation.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA GOLD;

CREATE OR REPLACE PROCEDURE GOLD.SP_DIM_PROVIDER_NETWORK(
    P_RUN_ID    VARCHAR,
    P_MODE      VARCHAR DEFAULT 'FULL'
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_step_run_id VARCHAR;
    v_insert_count NUMBER DEFAULT 0;
    v_err_msg VARCHAR;
BEGIN
    v_step_run_id := UUID_STRING();
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 31, 'DIM_PROVIDER_NETWORK', 'GOLD', 1);

    TRUNCATE TABLE P360_SP.GOLD.DIM_PROVIDER_NETWORK;

    INSERT INTO P360_SP.GOLD.DIM_PROVIDER_NETWORK (
        provider_network_sk, network_affiliation_id, npi_number, network_name,
        network_tier, participation_status, effective_date, termination_date,
        par_agreement_type, is_currently_participating, tenure_days,
        _source_loaded_at, _loaded_at, _run_id
    )
    SELECT
        affiliation_sk AS provider_network_sk,
        network_affiliation_id,
        npi_number,
        network_name,
        network_tier,
        participation_status,
        effective_date,
        termination_date,
        par_agreement_type,
        is_currently_participating,
        CASE
            WHEN termination_date IS NOT NULL THEN DATEDIFF('DAY', effective_date, termination_date)
            ELSE DATEDIFF('DAY', effective_date, CURRENT_DATE())
        END AS tenure_days,
        _source_loaded_at,
        CURRENT_TIMESTAMP() AS _loaded_at,
        :P_RUN_ID AS _run_id
    FROM P360_SP.SILVER.INT_NETWORK_AFFILIATIONS;

    v_insert_count := SQLROWCOUNT;

    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_insert_count, :v_insert_count, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_written', :v_insert_count);

EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'DIM_PROVIDER_NETWORK', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', 0, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
