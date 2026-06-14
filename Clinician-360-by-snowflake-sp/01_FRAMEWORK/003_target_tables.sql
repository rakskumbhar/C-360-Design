/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  01_FRAMEWORK/003_target_tables.sql
  
  Purpose: Creates all target tables for Bronze, Silver, Gold layers.
           These are the tables that stored procedures will write into.
=============================================================================*/

USE DATABASE P360_SP;

-- ============================================================
-- BRONZE LAYER TABLES (Staged/Cleaned)
-- ============================================================
USE SCHEMA BRONZE;

CREATE TABLE IF NOT EXISTS STG_NPI_REGISTRY (
    npi_number          VARCHAR(10),
    first_name          VARCHAR(200),
    last_name           VARCHAR(200),
    credentials         VARCHAR(200),
    gender_code         VARCHAR(1),
    entity_type_code    VARCHAR(1),
    is_sole_proprietor  VARCHAR(1),
    enumeration_date    DATE,
    last_update_date    DATE,
    deactivation_date   DATE,
    reactivation_date   DATE,
    npi_status          VARCHAR(1),
    _source_loaded_at   TIMESTAMP_NTZ,
    _stg_loaded_at      TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id             VARCHAR(36)
);

CREATE TABLE IF NOT EXISTS STG_CRED_PROVIDERS (
    credentialing_id    VARCHAR(200),
    npi_number          VARCHAR(10),
    specialty_code      VARCHAR(50),
    specialty_description VARCHAR(200),
    board_certification VARCHAR(200),
    credential_status   VARCHAR(50),
    credential_effective_date DATE,
    credential_expiry_date DATE,
    primary_taxonomy_code VARCHAR(50),
    _source_loaded_at   TIMESTAMP_NTZ,
    _stg_loaded_at      TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id             VARCHAR(36)
);

CREATE TABLE IF NOT EXISTS STG_EMR_PROVIDERS (
    emr_provider_id     VARCHAR(200),
    npi_number          VARCHAR(10),
    facility_name       VARCHAR(500),
    address_line_1      VARCHAR(500),
    address_line_2      VARCHAR(500),
    city                VARCHAR(200),
    state_code          VARCHAR(2),
    zip_code            VARCHAR(10),
    phone_number        VARCHAR(15),
    is_accepting_patients BOOLEAN,
    provider_status     VARCHAR(50),
    updated_at          TIMESTAMP_NTZ,
    _source_loaded_at   TIMESTAMP_NTZ,
    _stg_loaded_at      TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id             VARCHAR(36)
);

CREATE TABLE IF NOT EXISTS STG_CLAIMS_PROVIDERS (
    claim_id            VARCHAR(200),
    npi_number          VARCHAR(10),
    patient_id          VARCHAR(200),
    service_date        DATE,
    procedure_code      VARCHAR(50),
    diagnosis_code      VARCHAR(50),
    allowed_amount      NUMBER(12,2),
    paid_amount         NUMBER(12,2),
    claim_status        VARCHAR(50),
    network_status      VARCHAR(50),
    _source_loaded_at   TIMESTAMP_NTZ,
    _stg_loaded_at      TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id             VARCHAR(36)
);

CREATE TABLE IF NOT EXISTS STG_NETWORK_AFFILIATIONS (
    network_affiliation_id VARCHAR(200),
    npi_number          VARCHAR(10),
    network_name        VARCHAR(500),
    network_tier        VARCHAR(50),
    participation_status VARCHAR(50),
    effective_date      DATE,
    termination_date    DATE,
    par_agreement_type  VARCHAR(100),
    _source_loaded_at   TIMESTAMP_NTZ,
    _stg_loaded_at      TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id             VARCHAR(36)
);

-- ============================================================
-- SILVER LAYER TABLES (Intermediate/Unified)
-- ============================================================
USE SCHEMA SILVER;

CREATE TABLE IF NOT EXISTS INT_PROVIDERS_UNIFIED (
    npi_number              VARCHAR(10),
    first_name              VARCHAR(200),
    last_name               VARCHAR(200),
    credentials             VARCHAR(200),
    gender_code             VARCHAR(1),
    entity_type_code        VARCHAR(1),
    is_sole_proprietor      VARCHAR(1),
    npi_status              VARCHAR(1),
    enumeration_date        DATE,
    deactivation_date       DATE,
    reactivation_date       DATE,
    specialty_code          VARCHAR(50),
    specialty_description   VARCHAR(200),
    primary_taxonomy_code   VARCHAR(50),
    board_certification     VARCHAR(200),
    credential_status       VARCHAR(50),
    credential_effective_date DATE,
    credential_expiry_date  DATE,
    facility_name           VARCHAR(500),
    address_line_1          VARCHAR(500),
    address_line_2          VARCHAR(500),
    city                    VARCHAR(200),
    state_code              VARCHAR(2),
    zip_code                VARCHAR(10),
    phone_number            VARCHAR(15),
    is_accepting_patients   BOOLEAN,
    provider_status         VARCHAR(50),
    _source_loaded_at       TIMESTAMP_NTZ,
    _unified_at             TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id                 VARCHAR(36)
);

CREATE TABLE IF NOT EXISTS INT_PROVIDERS_DEDUPED (
    provider_dedup_key  VARCHAR(32),
    npi_number          VARCHAR(10),
    first_name          VARCHAR(200),
    last_name           VARCHAR(200),
    credentials         VARCHAR(200),
    gender_code         VARCHAR(1),
    entity_type_code    VARCHAR(1),
    is_sole_proprietor  VARCHAR(1),
    npi_status          VARCHAR(1),
    enumeration_date    DATE,
    deactivation_date   DATE,
    reactivation_date   DATE,
    specialty_code      VARCHAR(50),
    specialty_description VARCHAR(200),
    primary_taxonomy_code VARCHAR(50),
    board_certification VARCHAR(200),
    credential_status   VARCHAR(50),
    credential_effective_date DATE,
    credential_expiry_date DATE,
    facility_name       VARCHAR(500),
    address_line_1      VARCHAR(500),
    address_line_2      VARCHAR(500),
    city                VARCHAR(200),
    state_code          VARCHAR(2),
    zip_code            VARCHAR(10),
    phone_number        VARCHAR(15),
    is_accepting_patients BOOLEAN,
    provider_status     VARCHAR(50),
    source_system       VARCHAR(50),
    _source_loaded_at   TIMESTAMP_NTZ,
    _unified_at         TIMESTAMP_NTZ,
    _deduped_at         TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id             VARCHAR(36)
);

CREATE TABLE IF NOT EXISTS INT_NETWORK_AFFILIATIONS (
    affiliation_sk          VARCHAR(32),
    network_affiliation_id  VARCHAR(200),
    npi_number              VARCHAR(10),
    network_name            VARCHAR(500),
    network_tier            VARCHAR(50),
    participation_status    VARCHAR(50),
    effective_date          DATE,
    termination_date        DATE,
    par_agreement_type      VARCHAR(100),
    is_currently_participating BOOLEAN,
    _source_loaded_at       TIMESTAMP_NTZ,
    _enriched_at            TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id                 VARCHAR(36)
);

-- ============================================================
-- SNAPSHOT/SCD2 TABLE
-- ============================================================
USE SCHEMA SNAPSHOTS;

CREATE TABLE IF NOT EXISTS SCD2_PROVIDER_ATTRIBUTES (
    scd_key             VARCHAR(32)     NOT NULL,
    npi_number          VARCHAR(10)     NOT NULL,
    first_name          VARCHAR(200),
    last_name           VARCHAR(200),
    credentials         VARCHAR(200),
    gender_code         VARCHAR(1),
    entity_type_code    VARCHAR(1),
    is_sole_proprietor  VARCHAR(1),
    npi_status          VARCHAR(1),
    enumeration_date    DATE,
    deactivation_date   DATE,
    reactivation_date   DATE,
    specialty_code      VARCHAR(50),
    specialty_description VARCHAR(200),
    primary_taxonomy_code VARCHAR(50),
    board_certification VARCHAR(200),
    credential_status   VARCHAR(50),
    credential_effective_date DATE,
    credential_expiry_date DATE,
    facility_name       VARCHAR(500),
    address_line_1      VARCHAR(500),
    address_line_2      VARCHAR(500),
    city                VARCHAR(200),
    state_code          VARCHAR(2),
    zip_code            VARCHAR(10),
    phone_number        VARCHAR(15),
    is_accepting_patients BOOLEAN,
    provider_status     VARCHAR(50),
    _valid_from         TIMESTAMP_NTZ   NOT NULL,
    _valid_to           TIMESTAMP_NTZ   DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    _is_current         BOOLEAN         DEFAULT TRUE,
    _hash_diff          VARCHAR(32),
    _run_id             VARCHAR(36)
);

-- ============================================================
-- GOLD LAYER TABLES
-- ============================================================
USE SCHEMA GOLD;

CREATE TABLE IF NOT EXISTS DIM_PROVIDER (
    provider_sk         VARCHAR(32)     NOT NULL,
    npi_number          VARCHAR(10)     NOT NULL,
    valid_from          TIMESTAMP_NTZ   NOT NULL,
    valid_to            TIMESTAMP_NTZ   NOT NULL,
    is_current          BOOLEAN         NOT NULL,
    first_name          VARCHAR(200),
    last_name           VARCHAR(200),
    full_name           VARCHAR(400),
    credentials         VARCHAR(200),
    gender_code         VARCHAR(1),
    gender_description  VARCHAR(20),
    entity_type_code    VARCHAR(1),
    entity_type         VARCHAR(20),
    is_sole_proprietor  VARCHAR(1),
    npi_status          VARCHAR(1),
    npi_status_description VARCHAR(20),
    enumeration_date    DATE,
    deactivation_date   DATE,
    reactivation_date   DATE,
    is_npi_active       BOOLEAN,
    specialty_code      VARCHAR(50),
    specialty_description VARCHAR(200),
    primary_taxonomy_code VARCHAR(50),
    board_certification VARCHAR(200),
    credential_status   VARCHAR(50),
    credential_effective_date DATE,
    credential_expiry_date DATE,
    is_credentialed     BOOLEAN,
    facility_name       VARCHAR(500),
    address_line_1      VARCHAR(500),
    address_line_2      VARCHAR(500),
    city                VARCHAR(200),
    state_code          VARCHAR(2),
    zip_code            VARCHAR(10),
    phone_number        VARCHAR(15),
    is_accepting_patients BOOLEAN,
    provider_status     VARCHAR(50),
    is_fully_active     BOOLEAN,
    _record_updated_at  TIMESTAMP_NTZ,
    _loaded_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id             VARCHAR(36)
);

CREATE TABLE IF NOT EXISTS DIM_PROVIDER_NETWORK (
    provider_network_sk     VARCHAR(32)     NOT NULL,
    network_affiliation_id  VARCHAR(200),
    npi_number              VARCHAR(10)     NOT NULL,
    network_name            VARCHAR(500),
    network_tier            VARCHAR(50),
    participation_status    VARCHAR(50),
    effective_date          DATE,
    termination_date        DATE,
    par_agreement_type      VARCHAR(100),
    is_currently_participating BOOLEAN,
    tenure_days             NUMBER,
    _source_loaded_at       TIMESTAMP_NTZ,
    _loaded_at              TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id                 VARCHAR(36)
);

CREATE TABLE IF NOT EXISTS FCT_PROVIDER_VISITS (
    visit_sk            VARCHAR(32)     NOT NULL,
    claim_id            VARCHAR(200),
    npi_number          VARCHAR(10)     NOT NULL,
    patient_id          VARCHAR(200),
    service_date        DATE,
    procedure_code      VARCHAR(50),
    diagnosis_code      VARCHAR(50),
    allowed_amount      NUMBER(12,2),
    paid_amount         NUMBER(12,2),
    claim_status        VARCHAR(50),
    network_status      VARCHAR(50),
    net_paid_amount     NUMBER(12,2),
    patient_responsibility NUMBER(12,2),
    _source_loaded_at   TIMESTAMP_NTZ,
    _loaded_at          TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id             VARCHAR(36)
);

CREATE TABLE IF NOT EXISTS PROVIDER_360_SUMMARY (
    npi_number              VARCHAR(10)     NOT NULL,
    first_name              VARCHAR(200),
    last_name               VARCHAR(200),
    full_name               VARCHAR(400),
    credentials             VARCHAR(200),
    gender_code             VARCHAR(1),
    entity_type_code        VARCHAR(1),
    npi_status              VARCHAR(1),
    specialty_code          VARCHAR(50),
    specialty_description   VARCHAR(200),
    primary_taxonomy_code   VARCHAR(50),
    board_certification     VARCHAR(200),
    credential_status       VARCHAR(50),
    credential_effective_date DATE,
    credential_expiry_date  DATE,
    facility_name           VARCHAR(500),
    city                    VARCHAR(200),
    state_code              VARCHAR(2),
    zip_code                VARCHAR(10),
    phone_number            VARCHAR(15),
    is_accepting_patients   BOOLEAN,
    provider_status         VARCHAR(50),
    is_fully_active         BOOLEAN,
    total_claims            NUMBER          DEFAULT 0,
    unique_patients         NUMBER          DEFAULT 0,
    total_allowed_amount    NUMBER(14,2)    DEFAULT 0,
    total_paid_amount       NUMBER(14,2)    DEFAULT 0,
    first_service_date      DATE,
    last_service_date       DATE,
    denied_claims           NUMBER          DEFAULT 0,
    denial_rate_pct         NUMBER(5,2)     DEFAULT 0,
    total_networks          NUMBER          DEFAULT 0,
    active_networks         NUMBER          DEFAULT 0,
    active_network_list     VARCHAR(4000),
    _loaded_at              TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _run_id                 VARCHAR(36)
);

-- ============================================================
-- GOLD VIEWS (Consumer-facing)
-- ============================================================
CREATE OR REPLACE VIEW GOLD.VW_DIM_PROVIDER_CURRENT AS
SELECT * FROM P360_SP.GOLD.DIM_PROVIDER WHERE is_current = TRUE;

CREATE OR REPLACE VIEW GOLD.VW_FCT_PROVIDER_VISITS AS
SELECT
    visit_sk, claim_id, npi_number, patient_id, service_date,
    procedure_code, diagnosis_code, allowed_amount, paid_amount,
    net_paid_amount, patient_responsibility, claim_status, network_status,
    _loaded_at
FROM P360_SP.GOLD.FCT_PROVIDER_VISITS;
