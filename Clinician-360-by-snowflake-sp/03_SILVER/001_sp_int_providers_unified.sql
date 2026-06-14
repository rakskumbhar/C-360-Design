/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  03_SILVER/001_sp_int_providers_unified.sql
  
  Purpose: Unifies provider data from NPI Registry, Credentialing, and EMR 
           sources into a single consolidated provider record.
  
  Logic: LEFT JOIN NPI (master) with latest active credential and latest EMR.
         Uses incremental high-water-mark processing.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA SILVER;

CREATE OR REPLACE PROCEDURE SILVER.SP_INT_PROVIDERS_UNIFIED(
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
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 10, 'INT_PROVIDERS_UNIFIED', 'SILVER', 1);

    IF (:P_MODE = 'INCREMENTAL') THEN
        SELECT COALESCE(MAX(_source_loaded_at), '1900-01-01'::TIMESTAMP_NTZ) INTO v_hwm
        FROM P360_SP.SILVER.INT_PROVIDERS_UNIFIED;
    ELSE
        v_hwm := '1900-01-01'::TIMESTAMP_NTZ;
        TRUNCATE TABLE P360_SP.SILVER.INT_PROVIDERS_UNIFIED;
    END IF;

    CREATE OR REPLACE TEMPORARY TABLE _tmp_unified AS
    WITH npi AS (
        SELECT * FROM P360_SP.BRONZE.STG_NPI_REGISTRY
        WHERE _source_loaded_at > :v_hwm
    ),
    cred AS (
        SELECT * FROM P360_SP.BRONZE.STG_CRED_PROVIDERS
        WHERE credential_status = 'ACTIVE'
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY npi_number
            ORDER BY credential_effective_date DESC
        ) = 1
    ),
    emr AS (
        SELECT * FROM P360_SP.BRONZE.STG_EMR_PROVIDERS
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY npi_number
            ORDER BY updated_at DESC
        ) = 1
    )
    SELECT
        n.npi_number,
        n.first_name,
        n.last_name,
        n.credentials,
        n.gender_code,
        n.entity_type_code,
        n.is_sole_proprietor,
        n.npi_status,
        n.enumeration_date,
        n.deactivation_date,
        n.reactivation_date,
        c.specialty_code,
        c.specialty_description,
        c.primary_taxonomy_code,
        c.board_certification,
        c.credential_status,
        c.credential_effective_date,
        c.credential_expiry_date,
        e.facility_name,
        e.address_line_1,
        e.address_line_2,
        e.city,
        e.state_code,
        e.zip_code,
        e.phone_number,
        e.is_accepting_patients,
        e.provider_status,
        GREATEST(
            n._source_loaded_at,
            COALESCE(c._source_loaded_at, '1900-01-01'::TIMESTAMP_NTZ),
            COALESCE(e._source_loaded_at, '1900-01-01'::TIMESTAMP_NTZ)
        ) AS _source_loaded_at,
        CURRENT_TIMESTAMP() AS _unified_at,
        :P_RUN_ID AS _run_id
    FROM npi n
    LEFT JOIN cred c ON n.npi_number = c.npi_number
    LEFT JOIN emr e ON n.npi_number = e.npi_number;

    SELECT COUNT(*) INTO v_total_count FROM _tmp_unified;

    IF (v_total_count = 0) THEN
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', 0, 0, 0, 0, NULL, NULL, NULL);
        RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', 0, 'rows_written', 0);
    END IF;

    MERGE INTO P360_SP.SILVER.INT_PROVIDERS_UNIFIED tgt
    USING _tmp_unified src
    ON tgt.npi_number = src.npi_number
    WHEN MATCHED THEN UPDATE SET
        first_name = src.first_name,
        last_name = src.last_name,
        credentials = src.credentials,
        gender_code = src.gender_code,
        entity_type_code = src.entity_type_code,
        is_sole_proprietor = src.is_sole_proprietor,
        npi_status = src.npi_status,
        enumeration_date = src.enumeration_date,
        deactivation_date = src.deactivation_date,
        reactivation_date = src.reactivation_date,
        specialty_code = src.specialty_code,
        specialty_description = src.specialty_description,
        primary_taxonomy_code = src.primary_taxonomy_code,
        board_certification = src.board_certification,
        credential_status = src.credential_status,
        credential_effective_date = src.credential_effective_date,
        credential_expiry_date = src.credential_expiry_date,
        facility_name = src.facility_name,
        address_line_1 = src.address_line_1,
        address_line_2 = src.address_line_2,
        city = src.city,
        state_code = src.state_code,
        zip_code = src.zip_code,
        phone_number = src.phone_number,
        is_accepting_patients = src.is_accepting_patients,
        provider_status = src.provider_status,
        _source_loaded_at = src._source_loaded_at,
        _unified_at = src._unified_at,
        _run_id = src._run_id
    WHEN NOT MATCHED THEN INSERT (
        npi_number, first_name, last_name, credentials, gender_code,
        entity_type_code, is_sole_proprietor, npi_status, enumeration_date,
        deactivation_date, reactivation_date, specialty_code, specialty_description,
        primary_taxonomy_code, board_certification, credential_status,
        credential_effective_date, credential_expiry_date, facility_name,
        address_line_1, address_line_2, city, state_code, zip_code,
        phone_number, is_accepting_patients, provider_status,
        _source_loaded_at, _unified_at, _run_id
    ) VALUES (
        src.npi_number, src.first_name, src.last_name, src.credentials, src.gender_code,
        src.entity_type_code, src.is_sole_proprietor, src.npi_status, src.enumeration_date,
        src.deactivation_date, src.reactivation_date, src.specialty_code, src.specialty_description,
        src.primary_taxonomy_code, src.board_certification, src.credential_status,
        src.credential_effective_date, src.credential_expiry_date, src.facility_name,
        src.address_line_1, src.address_line_2, src.city, src.state_code, src.zip_code,
        src.phone_number, src.is_accepting_patients, src.provider_status,
        src._source_loaded_at, src._unified_at, src._run_id
    );

    v_insert_count := SQLROWCOUNT;
    DROP TABLE IF EXISTS _tmp_unified;

    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_total_count, :v_insert_count, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', :v_total_count, 'rows_written', :v_insert_count);

EXCEPTION
    WHEN OTHER THEN
        DROP TABLE IF EXISTS _tmp_unified;
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'INT_PROVIDERS_UNIFIED', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
