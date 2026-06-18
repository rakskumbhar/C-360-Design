select* 
    FROM P360_SP.SILVER.INT_PROVIDERS_UNIFIED
    where npi_number='1234567890'
    ;

select current_date()
;
select* from P360_SP.BRONZE.STG_EMR_PROVIDERS
 where npi_number='1234567890'

;
SET v_hwm = '2026-06-01';

    WITH npi AS (
        SELECT * FROM P360_SP.BRONZE.STG_NPI_REGISTRY
        WHERE _source_loaded_at > '2026-06-01'
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
        '' AS _run_id
    FROM npi n
    LEFT JOIN cred c ON n.npi_number = c.npi_number
    LEFT JOIN emr e ON n.npi_number = e.npi_number
    
     where n.npi_number='1234567890'
    ;