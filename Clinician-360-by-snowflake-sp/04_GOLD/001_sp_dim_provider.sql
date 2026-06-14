/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  04_GOLD/001_sp_dim_provider.sql
  
  Purpose: Builds the Provider dimension from SCD2 snapshot data.
           Includes derived attributes and business classifications.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA GOLD;

CREATE OR REPLACE PROCEDURE GOLD.SP_DIM_PROVIDER(
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
    v_total_count NUMBER DEFAULT 0;
    v_insert_count NUMBER DEFAULT 0;
    v_err_msg VARCHAR;
BEGIN
    v_step_run_id := UUID_STRING();
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 30, 'DIM_PROVIDER', 'GOLD', 1);

    TRUNCATE TABLE P360_SP.GOLD.DIM_PROVIDER;

    INSERT INTO P360_SP.GOLD.DIM_PROVIDER (
        provider_sk, npi_number, valid_from, valid_to, is_current,
        first_name, last_name, full_name, credentials, gender_code,
        gender_description, entity_type_code, entity_type, is_sole_proprietor,
        npi_status, npi_status_description, enumeration_date, deactivation_date,
        reactivation_date, is_npi_active, specialty_code, specialty_description,
        primary_taxonomy_code, board_certification, credential_status,
        credential_effective_date, credential_expiry_date, is_credentialed,
        facility_name, address_line_1, address_line_2, city, state_code,
        zip_code, phone_number, is_accepting_patients, provider_status,
        is_fully_active, _record_updated_at, _loaded_at, _run_id
    )
    SELECT
        MD5(npi_number || '|' || CAST(_valid_from AS VARCHAR)) AS provider_sk,
        npi_number,
        _valid_from AS valid_from,
        COALESCE(_valid_to, '9999-12-31'::TIMESTAMP_NTZ) AS valid_to,
        _is_current AS is_current,
        first_name,
        last_name,
        TRIM(first_name || ' ' || last_name) AS full_name,
        credentials,
        gender_code,
        CASE gender_code
            WHEN 'M' THEN 'Male'
            WHEN 'F' THEN 'Female'
            ELSE 'Unknown'
        END AS gender_description,
        entity_type_code,
        CASE entity_type_code
            WHEN '1' THEN 'Individual'
            WHEN '2' THEN 'Organization'
            ELSE 'Unknown'
        END AS entity_type,
        is_sole_proprietor,
        npi_status,
        CASE npi_status
            WHEN 'A' THEN 'Active'
            WHEN 'D' THEN 'Deactivated'
            WHEN 'R' THEN 'Retired'
            ELSE 'Unknown'
        END AS npi_status_description,
        enumeration_date,
        deactivation_date,
        reactivation_date,
        (npi_status = 'A' AND deactivation_date IS NULL)::BOOLEAN AS is_npi_active,
        specialty_code,
        specialty_description,
        primary_taxonomy_code,
        board_certification,
        credential_status,
        credential_effective_date,
        credential_expiry_date,
        (credential_status = 'ACTIVE'
            AND (credential_expiry_date IS NULL OR credential_expiry_date >= CURRENT_DATE())
        )::BOOLEAN AS is_credentialed,
        facility_name,
        address_line_1,
        address_line_2,
        city,
        state_code,
        zip_code,
        phone_number,
        is_accepting_patients,
        provider_status,
        (npi_status = 'A'
            AND deactivation_date IS NULL
            AND credential_status = 'ACTIVE'
            AND (credential_expiry_date IS NULL OR credential_expiry_date >= CURRENT_DATE())
            AND provider_status = 'ACTIVE'
        )::BOOLEAN AS is_fully_active,
        _valid_from AS _record_updated_at,
        CURRENT_TIMESTAMP() AS _loaded_at,
        :P_RUN_ID AS _run_id
    FROM P360_SP.SNAPSHOTS.SCD2_PROVIDER_ATTRIBUTES;

    v_insert_count := SQLROWCOUNT;

    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_insert_count, :v_insert_count, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_written', :v_insert_count);

EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'DIM_PROVIDER', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', 0, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
