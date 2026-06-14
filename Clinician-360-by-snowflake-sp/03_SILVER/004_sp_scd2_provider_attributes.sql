/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  03_SILVER/004_sp_scd2_provider_attributes.sql
  
  Purpose: Implements SCD Type-2 tracking for provider attributes.
           Detects changes via hash comparison and creates new versions.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA SILVER;

CREATE OR REPLACE PROCEDURE SILVER.SP_SCD2_PROVIDER_ATTRIBUTES(
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
    v_new_count NUMBER DEFAULT 0;
    v_changed_count NUMBER DEFAULT 0;
    v_enable_scd2 VARCHAR;
    v_err_msg VARCHAR;
BEGIN
    v_step_run_id := UUID_STRING();
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 20, 'SCD2_PROVIDER_ATTRIBUTES', 'SILVER', 1);

    SELECT config_value INTO v_enable_scd2 FROM P360_SP.CONFIG.PKG_CONFIG WHERE config_key = 'ENABLE_SCD2';
    IF (v_enable_scd2 != 'TRUE') THEN
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'SKIPPED', 0, 0, 0, 0, 'SCD2 disabled by config', NULL, NULL);
        RETURN OBJECT_CONSTRUCT('status', 'SKIPPED', 'reason', 'SCD2_DISABLED');
    END IF;

    CREATE OR REPLACE TEMPORARY TABLE _tmp_scd2_source AS
    SELECT
        npi_number,
        first_name, last_name, credentials, gender_code, entity_type_code,
        is_sole_proprietor, npi_status, enumeration_date, deactivation_date,
        reactivation_date, specialty_code, specialty_description,
        primary_taxonomy_code, board_certification, credential_status,
        credential_effective_date, credential_expiry_date, facility_name,
        address_line_1, address_line_2, city, state_code, zip_code,
        phone_number, is_accepting_patients, provider_status,
        MD5(
            COALESCE(npi_status, '') || '|' ||
            COALESCE(specialty_code, '') || '|' ||
            COALESCE(primary_taxonomy_code, '') || '|' ||
            COALESCE(board_certification, '') || '|' ||
            COALESCE(credential_status, '') || '|' ||
            COALESCE(facility_name, '') || '|' ||
            COALESCE(address_line_1, '') || '|' ||
            COALESCE(city, '') || '|' ||
            COALESCE(state_code, '') || '|' ||
            COALESCE(zip_code, '') || '|' ||
            COALESCE(CAST(is_accepting_patients AS VARCHAR), '') || '|' ||
            COALESCE(provider_status, '') || '|' ||
            COALESCE(CAST(deactivation_date AS VARCHAR), '') || '|' ||
            COALESCE(CAST(reactivation_date AS VARCHAR), '')
        ) AS _hash_diff
    FROM P360_SP.SILVER.INT_PROVIDERS_UNIFIED;

    SELECT COUNT(*) INTO v_total_count FROM _tmp_scd2_source;

    UPDATE P360_SP.SNAPSHOTS.SCD2_PROVIDER_ATTRIBUTES tgt
    SET _valid_to = CURRENT_TIMESTAMP(),
        _is_current = FALSE
    WHERE tgt._is_current = TRUE
      AND EXISTS (
          SELECT 1 FROM _tmp_scd2_source src
          WHERE src.npi_number = tgt.npi_number
            AND src._hash_diff != tgt._hash_diff
      );

    v_changed_count := SQLROWCOUNT;

    INSERT INTO P360_SP.SNAPSHOTS.SCD2_PROVIDER_ATTRIBUTES (
        scd_key, npi_number, first_name, last_name, credentials, gender_code,
        entity_type_code, is_sole_proprietor, npi_status, enumeration_date,
        deactivation_date, reactivation_date, specialty_code, specialty_description,
        primary_taxonomy_code, board_certification, credential_status,
        credential_effective_date, credential_expiry_date, facility_name,
        address_line_1, address_line_2, city, state_code, zip_code,
        phone_number, is_accepting_patients, provider_status,
        _valid_from, _valid_to, _is_current, _hash_diff, _run_id
    )
    SELECT
        MD5(src.npi_number || '|' || CAST(CURRENT_TIMESTAMP() AS VARCHAR)),
        src.npi_number, src.first_name, src.last_name, src.credentials, src.gender_code,
        src.entity_type_code, src.is_sole_proprietor, src.npi_status, src.enumeration_date,
        src.deactivation_date, src.reactivation_date, src.specialty_code, src.specialty_description,
        src.primary_taxonomy_code, src.board_certification, src.credential_status,
        src.credential_effective_date, src.credential_expiry_date, src.facility_name,
        src.address_line_1, src.address_line_2, src.city, src.state_code, src.zip_code,
        src.phone_number, src.is_accepting_patients, src.provider_status,
        CURRENT_TIMESTAMP(), '9999-12-31'::TIMESTAMP_NTZ, TRUE, src._hash_diff, :P_RUN_ID
    FROM _tmp_scd2_source src
    WHERE NOT EXISTS (
        SELECT 1 FROM P360_SP.SNAPSHOTS.SCD2_PROVIDER_ATTRIBUTES tgt
        WHERE tgt.npi_number = src.npi_number
          AND tgt._is_current = TRUE
          AND tgt._hash_diff = src._hash_diff
    );

    v_new_count := SQLROWCOUNT;
    DROP TABLE IF EXISTS _tmp_scd2_source;

    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_total_count, :v_new_count, 0, :v_changed_count, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_read', :v_total_count, 'new_versions', :v_new_count, 'closed_versions', :v_changed_count);

EXCEPTION
    WHEN OTHER THEN
        DROP TABLE IF EXISTS _tmp_scd2_source;
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'SCD2_PROVIDER_ATTRIBUTES', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', :v_total_count, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
