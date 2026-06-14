/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  04_GOLD/004_sp_provider_360_summary.sql
  
  Purpose: Builds the One Big Table (OBT) Provider 360 Summary combining
           provider demographics, claims aggregates, and network participation.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA GOLD;

CREATE OR REPLACE PROCEDURE GOLD.SP_PROVIDER_360_SUMMARY(
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
    CALL P360_SP.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 33, 'PROVIDER_360_SUMMARY', 'GOLD', 1);

    TRUNCATE TABLE P360_SP.GOLD.PROVIDER_360_SUMMARY;

    INSERT INTO P360_SP.GOLD.PROVIDER_360_SUMMARY (
        npi_number, first_name, last_name, full_name, credentials, gender_code,
        entity_type_code, npi_status, specialty_code, specialty_description,
        primary_taxonomy_code, board_certification, credential_status,
        credential_effective_date, credential_expiry_date, facility_name,
        city, state_code, zip_code, phone_number, is_accepting_patients,
        provider_status, is_fully_active, total_claims, unique_patients,
        total_allowed_amount, total_paid_amount, first_service_date,
        last_service_date, denied_claims, denial_rate_pct,
        total_networks, active_networks, active_network_list,
        _loaded_at, _run_id
    )
    WITH providers AS (
        SELECT * FROM P360_SP.SILVER.INT_PROVIDERS_DEDUPED
    ),
    visits_agg AS (
        SELECT
            npi_number,
            COUNT(DISTINCT claim_id) AS total_claims,
            COUNT(DISTINCT patient_id) AS unique_patients,
            SUM(allowed_amount) AS total_allowed_amount,
            SUM(paid_amount) AS total_paid_amount,
            MIN(service_date) AS first_service_date,
            MAX(service_date) AS last_service_date,
            SUM(CASE WHEN claim_status = 'DENIED' THEN 1 ELSE 0 END) AS denied_claims,
            ROUND(
                SUM(CASE WHEN claim_status = 'DENIED' THEN 1 ELSE 0 END)::FLOAT
                / NULLIF(COUNT(*), 0) * 100, 2
            ) AS denial_rate_pct
        FROM P360_SP.BRONZE.STG_CLAIMS_PROVIDERS
        GROUP BY 1
    ),
    network_agg AS (
        SELECT
            npi_number,
            COUNT(DISTINCT network_name) AS total_networks,
            SUM(CASE WHEN is_currently_participating THEN 1 ELSE 0 END) AS active_networks,
            LISTAGG(CASE WHEN is_currently_participating THEN network_name END, ', ')
                WITHIN GROUP (ORDER BY network_name) AS active_network_list
        FROM P360_SP.SILVER.INT_NETWORK_AFFILIATIONS
        GROUP BY 1
    )
    SELECT
        p.npi_number,
        p.first_name,
        p.last_name,
        TRIM(p.first_name || ' ' || p.last_name) AS full_name,
        p.credentials,
        p.gender_code,
        p.entity_type_code,
        p.npi_status,
        p.specialty_code,
        p.specialty_description,
        p.primary_taxonomy_code,
        p.board_certification,
        p.credential_status,
        p.credential_effective_date,
        p.credential_expiry_date,
        p.facility_name,
        p.city,
        p.state_code,
        p.zip_code,
        p.phone_number,
        p.is_accepting_patients,
        p.provider_status,
        (p.npi_status = 'A'
            AND p.deactivation_date IS NULL
            AND p.credential_status = 'ACTIVE'
            AND (p.credential_expiry_date IS NULL OR p.credential_expiry_date >= CURRENT_DATE())
            AND p.provider_status = 'ACTIVE'
        )::BOOLEAN AS is_fully_active,
        COALESCE(v.total_claims, 0),
        COALESCE(v.unique_patients, 0),
        COALESCE(v.total_allowed_amount, 0),
        COALESCE(v.total_paid_amount, 0),
        v.first_service_date,
        v.last_service_date,
        COALESCE(v.denied_claims, 0),
        COALESCE(v.denial_rate_pct, 0),
        COALESCE(n.total_networks, 0),
        COALESCE(n.active_networks, 0),
        n.active_network_list,
        CURRENT_TIMESTAMP(),
        :P_RUN_ID
    FROM providers p
    LEFT JOIN visits_agg v ON p.npi_number = v.npi_number
    LEFT JOIN network_agg n ON p.npi_number = n.npi_number;

    v_insert_count := SQLROWCOUNT;

    CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_insert_count, :v_insert_count, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_written', :v_insert_count);

EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_SP.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'PROVIDER_360_SUMMARY', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_SP.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', 0, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
