/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  03_SILVER/002_sp_int_providers_deduped.sql
  
  Purpose: Deduplicates unified providers by NPI, keeping the most recent record.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA SILVER;

CREATE OR REPLACE PROCEDURE SILVER.SP_INT_PROVIDERS_DEDUPED(
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
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 11, 'INT_PROVIDERS_DEDUPED', 'SILVER', 1);

    IF (:P_MODE = 'INCREMENTAL') THEN
        SELECT COALESCE(MAX(_unified_at), '1900-01-01'::TIMESTAMP_NTZ) INTO v_hwm
        FROM P360_SP.SILVER.INT_PROVIDERS_DEDUPED;
    ELSE
        v_hwm := '1900-01-01'::TIMESTAMP_NTZ;
        TRUNCATE TABLE P360_SP.SILVER.INT_PROVIDERS_DEDUPED;
    END IF;

    CREATE OR REPLACE TEMPORARY TABLE _tmp_deduped AS
    SELECT
        MD5(COALESCE(CAST(npi_number AS VARCHAR), '_null_')) AS provider_dedup_key,
        npi_number, first_name, last_name, credentials, gender_code,
        entity_type_code, is_sole_proprietor, npi_status, enumeration_date,
        deactivation_date, reactivation_date, specialty_code, specialty_description,
        primary_taxonomy_code, board_certification, credential_status,
        credential_effective_date, credential_expiry_date, facility_name,
        address_line_1, address_line_2, city, state_code, zip_code,
        phone_number, is_accepting_patients, provider_status,
        'NPI_REGISTRY' AS source_system,
        _source_loaded_at, _unified_at,
        CURRENT_TIMESTAMP() AS _deduped_at,
        :P_RUN_ID AS _run_id
    FROM P360_SP.SILVER.INT_PROVIDERS_UNIFIED
    WHERE _unified_at > :v_hwm
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY npi_number
        ORDER BY _source_loaded_at DESC
    ) = 1;

    SELECT COUNT(*) INTO v_total_count FROM _tmp_deduped;

    IF (v_total_count = 0) THEN
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', 0, 0, 0, 0, NULL, NULL, NULL);
        RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', 0, 'rows_written', 0);
    END IF;

    MERGE INTO P360_SP.SILVER.INT_PROVIDERS_DEDUPED tgt
    USING _tmp_deduped src
    ON tgt.provider_dedup_key = src.provider_dedup_key
    WHEN MATCHED THEN UPDATE SET
        npi_number = src.npi_number, first_name = src.first_name, last_name = src.last_name,
        credentials = src.credentials, gender_code = src.gender_code,
        entity_type_code = src.entity_type_code, is_sole_proprietor = src.is_sole_proprietor,
        npi_status = src.npi_status, enumeration_date = src.enumeration_date,
        deactivation_date = src.deactivation_date, reactivation_date = src.reactivation_date,
        specialty_code = src.specialty_code, specialty_description = src.specialty_description,
        primary_taxonomy_code = src.primary_taxonomy_code, board_certification = src.board_certification,
        credential_status = src.credential_status, credential_effective_date = src.credential_effective_date,
        credential_expiry_date = src.credential_expiry_date, facility_name = src.facility_name,
        address_line_1 = src.address_line_1, address_line_2 = src.address_line_2,
        city = src.city, state_code = src.state_code, zip_code = src.zip_code,
        phone_number = src.phone_number, is_accepting_patients = src.is_accepting_patients,
        provider_status = src.provider_status, source_system = src.source_system,
        _source_loaded_at = src._source_loaded_at, _unified_at = src._unified_at,
        _deduped_at = src._deduped_at, _run_id = src._run_id
    WHEN NOT MATCHED THEN INSERT (
        provider_dedup_key, npi_number, first_name, last_name, credentials, gender_code,
        entity_type_code, is_sole_proprietor, npi_status, enumeration_date,
        deactivation_date, reactivation_date, specialty_code, specialty_description,
        primary_taxonomy_code, board_certification, credential_status,
        credential_effective_date, credential_expiry_date, facility_name,
        address_line_1, address_line_2, city, state_code, zip_code,
        phone_number, is_accepting_patients, provider_status, source_system,
        _source_loaded_at, _unified_at, _deduped_at, _run_id
    ) VALUES (
        src.provider_dedup_key, src.npi_number, src.first_name, src.last_name, src.credentials, src.gender_code,
        src.entity_type_code, src.is_sole_proprietor, src.npi_status, src.enumeration_date,
        src.deactivation_date, src.reactivation_date, src.specialty_code, src.specialty_description,
        src.primary_taxonomy_code, src.board_certification, src.credential_status,
        src.credential_effective_date, src.credential_expiry_date, src.facility_name,
        src.address_line_1, src.address_line_2, src.city, src.state_code, src.zip_code,
        src.phone_number, src.is_accepting_patients, src.provider_status, src.source_system,
        src._source_loaded_at, src._unified_at, src._deduped_at, src._run_id
    );

    v_insert_count := SQLROWCOUNT;
    DROP TABLE IF EXISTS _tmp_deduped;

    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_total_count, :v_insert_count, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', :v_total_count, 'rows_written', :v_insert_count);

EXCEPTION
    WHEN OTHER THEN
        DROP TABLE IF EXISTS _tmp_deduped;
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'INT_PROVIDERS_DEDUPED', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
