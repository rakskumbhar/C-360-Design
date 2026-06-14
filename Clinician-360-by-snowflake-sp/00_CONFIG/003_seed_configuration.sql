/*=============================================================================
  PROVIDER-360-BY-SNOWFLAKE-SP
  00_CONFIG/003_seed_configuration.sql
  
  Purpose: Seeds all configuration tables with default values for the 
           Provider 360 pipeline.
=============================================================================*/

USE DATABASE P360_SP;
USE SCHEMA CONFIG;

-- ============================================================
-- PACKAGE CONFIGURATION SEEDS
-- ============================================================
MERGE INTO PKG_CONFIG tgt
USING (
    SELECT * FROM VALUES
    ('PKG_NAME',            'PROVIDER_360_SP',   'STRING',  'GENERAL',      'Package name identifier'),
    ('PKG_VERSION',         '1.0.0',             'STRING',  'GENERAL',      'Current package version'),
    ('ENVIRONMENT',         'DEV',               'STRING',  'GENERAL',      'Current environment (DEV/QA/PROD)'),
    ('SOURCE_DATABASE',     'SNOWFLAKE_LEARNING_DB', 'STRING', 'SOURCE',   'Source database for raw data'),
    ('SOURCE_SCHEMA',       'RAW_INGESTION',     'STRING',  'SOURCE',       'Source schema for raw tables'),
    ('WAREHOUSE',           'COMPUTE_WH',        'STRING',  'COMPUTE',      'Warehouse for processing'),
    ('BATCH_SIZE',          '100000',            'NUMBER',  'PROCESSING',   'Records per batch for large tables'),
    ('MAX_RETRY_COUNT',     '3',                 'NUMBER',  'PROCESSING',   'Maximum retry attempts per step'),
    ('RETRY_DELAY_SEC',     '60',                'NUMBER',  'PROCESSING',   'Seconds between retries'),
    ('DQ_REJECT_THRESHOLD', '5.0',               'NUMBER',  'DATA_QUALITY', 'Max reject % before step fails'),
    ('ENABLE_EMAIL_NOTIFY', 'FALSE',             'BOOLEAN', 'NOTIFICATION', 'Enable email notifications'),
    ('EMAIL_INTEGRATION',   'P360_EMAIL_INT',    'STRING',  'NOTIFICATION', 'Email integration name'),
    ('NOTIFY_ON_SUCCESS',   'TRUE',              'BOOLEAN', 'NOTIFICATION', 'Send notification on success'),
    ('NOTIFY_ON_FAILURE',   'TRUE',              'BOOLEAN', 'NOTIFICATION', 'Send notification on failure'),
    ('LOG_RETENTION_DAYS',  '365',               'NUMBER',  'AUDIT',        'Days to retain run logs'),
    ('REJECT_RETENTION_DAYS','365',              'NUMBER',  'AUDIT',        'Days to retain reject records'),
    ('ENABLE_SCD2',         'TRUE',              'BOOLEAN', 'PROCESSING',   'Enable SCD Type-2 tracking'),
    ('INCREMENTAL_MODE',    'TRUE',              'BOOLEAN', 'PROCESSING',   'Enable incremental processing')
) AS src(config_key, config_value, config_data_type, config_category, description)
ON tgt.config_key = src.config_key
WHEN MATCHED THEN UPDATE SET
    config_value = src.config_value,
    updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT
    (config_key, config_value, config_data_type, config_category, description)
VALUES
    (src.config_key, src.config_value, src.config_data_type, src.config_category, src.description);

-- ============================================================
-- STEP REGISTRY SEEDS
-- ============================================================
MERGE INTO PKG_STEP_REGISTRY tgt
USING (
    SELECT * FROM VALUES
    (1,  'STG_NPI_REGISTRY',           'BRONZE', 'P360_SP.BRONZE.SP_STG_NPI_REGISTRY',              1.0, NULL, TRUE, TRUE, 3, 60, 30, 'Stage NPI registry data'),
    (2,  'STG_CRED_PROVIDERS',         'BRONZE', 'P360_SP.BRONZE.SP_STG_CRED_PROVIDERS',            1.1, NULL, TRUE, TRUE, 3, 60, 30, 'Stage credentialing data'),
    (3,  'STG_EMR_PROVIDERS',          'BRONZE', 'P360_SP.BRONZE.SP_STG_EMR_PROVIDERS',             1.2, NULL, TRUE, TRUE, 3, 60, 30, 'Stage EMR provider data'),
    (4,  'STG_CLAIMS_PROVIDERS',       'BRONZE', 'P360_SP.BRONZE.SP_STG_CLAIMS_PROVIDERS',          1.3, NULL, TRUE, TRUE, 3, 60, 60, 'Stage claims data'),
    (5,  'STG_NETWORK_AFFILIATIONS',   'BRONZE', 'P360_SP.BRONZE.SP_STG_NETWORK_AFFILIATIONS',     1.4, NULL, TRUE, TRUE, 3, 60, 30, 'Stage network affiliations'),
    (10, 'INT_PROVIDERS_UNIFIED',      'SILVER', 'P360_SP.SILVER.SP_INT_PROVIDERS_UNIFIED',        2.0, ARRAY_CONSTRUCT(1,2,3), TRUE, TRUE, 3, 60, 60, 'Unify provider data from NPI/Cred/EMR'),
    (11, 'INT_PROVIDERS_DEDUPED',      'SILVER', 'P360_SP.SILVER.SP_INT_PROVIDERS_DEDUPED',        2.1, ARRAY_CONSTRUCT(10), TRUE, TRUE, 3, 60, 30, 'Deduplicate unified providers'),
    (12, 'INT_NETWORK_AFFILIATIONS',   'SILVER', 'P360_SP.SILVER.SP_INT_NETWORK_AFFILIATIONS',    2.2, ARRAY_CONSTRUCT(5), TRUE, TRUE, 3, 60, 30, 'Enrich network affiliations'),
    (20, 'SCD2_PROVIDER_ATTRIBUTES',   'SILVER', 'P360_SP.SILVER.SP_SCD2_PROVIDER_ATTRIBUTES',    3.0, ARRAY_CONSTRUCT(10), TRUE, TRUE, 3, 60, 60, 'SCD2 provider attribute tracking'),
    (30, 'DIM_PROVIDER',               'GOLD',   'P360_SP.GOLD.SP_DIM_PROVIDER',                   4.0, ARRAY_CONSTRUCT(20), TRUE, TRUE, 3, 60, 30, 'Build provider dimension'),
    (31, 'DIM_PROVIDER_NETWORK',       'GOLD',   'P360_SP.GOLD.SP_DIM_PROVIDER_NETWORK',           4.1, ARRAY_CONSTRUCT(12), TRUE, TRUE, 3, 60, 30, 'Build provider network dimension'),
    (32, 'FCT_PROVIDER_VISITS',        'GOLD',   'P360_SP.GOLD.SP_FCT_PROVIDER_VISITS',            4.2, ARRAY_CONSTRUCT(4), TRUE, TRUE, 3, 60, 60, 'Build provider visits fact'),
    (33, 'PROVIDER_360_SUMMARY',       'GOLD',   'P360_SP.GOLD.SP_PROVIDER_360_SUMMARY',           4.3, ARRAY_CONSTRUCT(30,31,32), TRUE, TRUE, 3, 60, 60, 'Build Provider 360 OBT'),
    (40, 'AUDIT_REJECT_SUMMARY',       'AUDIT',  'P360_SP.AUDIT.SP_REJECT_SUMMARY',                5.0, ARRAY_CONSTRUCT(33), TRUE, TRUE, 3, 60, 15, 'Summarize rejects for current run'),
    (41, 'AUDIT_RUN_METADATA',         'AUDIT',  'P360_SP.AUDIT.SP_RUN_METADATA',                  5.1, ARRAY_CONSTRUCT(40), TRUE, TRUE, 3, 60, 15, 'Capture run metadata')
) AS src(step_id, step_name, step_layer, step_procedure, step_order, depends_on_step_id, is_active, is_restartable, retry_count, retry_delay_seconds, timeout_minutes, description)
ON tgt.step_id = src.step_id
WHEN MATCHED THEN UPDATE SET
    step_name = src.step_name,
    step_layer = src.step_layer,
    step_procedure = src.step_procedure,
    step_order = src.step_order,
    depends_on_step_id = src.depends_on_step_id,
    is_active = src.is_active,
    is_restartable = src.is_restartable,
    retry_count = src.retry_count,
    retry_delay_seconds = src.retry_delay_seconds,
    timeout_minutes = src.timeout_minutes,
    description = src.description,
    updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT
    (step_id, step_name, step_layer, step_procedure, step_order, depends_on_step_id, is_active, is_restartable, retry_count, retry_delay_seconds, timeout_minutes, description)
VALUES
    (src.step_id, src.step_name, src.step_layer, src.step_procedure, src.step_order, src.depends_on_step_id, src.is_active, src.is_restartable, src.retry_count, src.retry_delay_seconds, src.timeout_minutes, src.description);

-- ============================================================
-- DATA QUALITY RULES SEEDS
-- ============================================================
MERGE INTO DQ_RULES tgt
USING (
    SELECT * FROM VALUES
    -- NPI Registry Rules
    ('NPI_NOT_NULL',       'NPI_RAW',                'BRONZE', 'NPI_NUMBER',    'NOT_NULL',  'NPI_NUMBER IS NULL',                                    'NPI_NUMBER_NULL',        'ERROR'),
    ('NPI_LENGTH',         'NPI_RAW',                'BRONZE', 'NPI_NUMBER',    'LENGTH',    'LENGTH(NPI_NUMBER) != 10',                              'NPI_INVALID_LENGTH',     'ERROR'),
    ('NPI_NUMERIC',        'NPI_RAW',                'BRONZE', 'NPI_NUMBER',    'PATTERN',   'TRY_TO_NUMBER(NPI_NUMBER) IS NULL AND NPI_NUMBER IS NOT NULL', 'NPI_NON_NUMERIC', 'ERROR'),
    ('NPI_FNAME_NOT_NULL', 'NPI_RAW',                'BRONZE', 'PROVIDER_FIRST_NAME', 'NOT_NULL', 'PROVIDER_FIRST_NAME IS NULL',                     'FIRST_NAME_NULL',        'ERROR'),
    ('NPI_LNAME_NOT_NULL', 'NPI_RAW',                'BRONZE', 'PROVIDER_LAST_NAME_LEGAL', 'NOT_NULL', 'PROVIDER_LAST_NAME_LEGAL IS NULL',            'LAST_NAME_NULL',         'ERROR'),
    ('NPI_STATUS_VALID',   'NPI_RAW',                'BRONZE', 'STATUS',        'PATTERN',   'STATUS NOT IN (''A'',''D'',''R'') AND STATUS IS NOT NULL', 'INVALID_NPI_STATUS', 'ERROR'),
    -- Claims Rules
    ('CLM_ID_NOT_NULL',    'CLAIMS_RAW',             'BRONZE', 'CLAIM_ID',      'NOT_NULL',  'CLAIM_ID IS NULL',                                      'CLAIM_ID_NULL',          'ERROR'),
    ('CLM_NPI_NOT_NULL',   'CLAIMS_RAW',             'BRONZE', 'NPI_NUMBER',    'NOT_NULL',  'NPI_NUMBER IS NULL',                                    'NPI_NUMBER_NULL',        'ERROR'),
    ('CLM_NPI_LENGTH',     'CLAIMS_RAW',             'BRONZE', 'NPI_NUMBER',    'LENGTH',    'LENGTH(NPI_NUMBER) != 10',                              'NPI_INVALID_LENGTH',     'ERROR'),
    ('CLM_SVCDT_NOT_NULL', 'CLAIMS_RAW',             'BRONZE', 'SERVICE_DATE',  'NOT_NULL',  'SERVICE_DATE IS NULL',                                  'SERVICE_DATE_NULL',      'ERROR'),
    ('CLM_SVCDT_FUTURE',   'CLAIMS_RAW',             'BRONZE', 'SERVICE_DATE',  'RANGE',     'SERVICE_DATE > CURRENT_DATE()',                          'FUTURE_SERVICE_DATE',    'ERROR'),
    ('CLM_AMT_ALLOWED',    'CLAIMS_RAW',             'BRONZE', 'ALLOWED_AMOUNT','RANGE',     'ALLOWED_AMOUNT < 0',                                    'NEGATIVE_ALLOWED_AMOUNT','ERROR'),
    ('CLM_AMT_PAID',       'CLAIMS_RAW',             'BRONZE', 'PAID_AMOUNT',   'RANGE',     'PAID_AMOUNT < 0',                                       'NEGATIVE_PAID_AMOUNT',   'ERROR'),
    ('CLM_STATUS_VALID',   'CLAIMS_RAW',             'BRONZE', 'CLAIM_STATUS',  'PATTERN',   'CLAIM_STATUS NOT IN (''PAID'',''DENIED'',''PENDING'',''ADJUSTED'') AND CLAIM_STATUS IS NOT NULL', 'INVALID_CLAIM_STATUS', 'ERROR'),
    -- Credentialing Rules
    ('CRED_NPI_NOT_NULL',  'PROVIDER_CREDENTIALS_RAW','BRONZE','NPI_NUMBER',    'NOT_NULL',  'NPI_NUMBER IS NULL',                                    'NPI_NUMBER_NULL',        'ERROR'),
    ('CRED_NPI_LENGTH',    'PROVIDER_CREDENTIALS_RAW','BRONZE','NPI_NUMBER',    'LENGTH',    'LENGTH(NPI_NUMBER) != 10',                              'NPI_INVALID_LENGTH',     'ERROR'),
    ('CRED_STATUS_VALID',  'PROVIDER_CREDENTIALS_RAW','BRONZE','CREDENTIAL_STATUS','PATTERN','CREDENTIAL_STATUS NOT IN (''ACTIVE'',''INACTIVE'',''EXPIRED'',''PENDING'') AND CREDENTIAL_STATUS IS NOT NULL', 'INVALID_CRED_STATUS', 'ERROR'),
    -- EMR Rules
    ('EMR_NPI_NOT_NULL',   'PROVIDER_MASTER_RAW',    'BRONZE', 'NPI_NUMBER',    'NOT_NULL',  'NPI_NUMBER IS NULL',                                    'NPI_NUMBER_NULL',        'ERROR'),
    ('EMR_NPI_LENGTH',     'PROVIDER_MASTER_RAW',    'BRONZE', 'NPI_NUMBER',    'LENGTH',    'LENGTH(NPI_NUMBER) != 10',                              'NPI_INVALID_LENGTH',     'ERROR'),
    ('EMR_STATE_VALID',    'PROVIDER_MASTER_RAW',    'BRONZE', 'STATE_CODE',    'LENGTH',    'LENGTH(STATE_CODE) != 2 AND STATE_CODE IS NOT NULL',    'INVALID_STATE_CODE',     'WARNING'),
    -- Network Rules
    ('NET_NPI_NOT_NULL',   'NETWORK_AFFILIATIONS_RAW','BRONZE','NPI_NUMBER',    'NOT_NULL',  'NPI_NUMBER IS NULL',                                    'NPI_NUMBER_NULL',        'ERROR'),
    ('NET_NPI_LENGTH',     'NETWORK_AFFILIATIONS_RAW','BRONZE','NPI_NUMBER',    'LENGTH',    'LENGTH(NPI_NUMBER) != 10',                              'NPI_INVALID_LENGTH',     'ERROR'),
    ('NET_EFF_DT_NULL',    'NETWORK_AFFILIATIONS_RAW','BRONZE','EFFECTIVE_DATE','NOT_NULL',  'EFFECTIVE_DATE IS NULL',                                'EFFECTIVE_DATE_NULL',    'ERROR')
) AS src(rule_name, source_table, target_layer, column_name, rule_type, rule_expression, reject_reason_code, severity)
ON tgt.rule_name = src.rule_name AND tgt.source_table = src.source_table
WHEN MATCHED THEN UPDATE SET
    column_name = src.column_name,
    rule_type = src.rule_type,
    rule_expression = src.rule_expression,
    reject_reason_code = src.reject_reason_code,
    severity = src.severity,
    updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT
    (rule_name, source_table, target_layer, column_name, rule_type, rule_expression, reject_reason_code, severity)
VALUES
    (src.rule_name, src.source_table, src.target_layer, src.column_name, src.rule_type, src.rule_expression, src.reject_reason_code, src.severity);

-- ============================================================
-- ENVIRONMENT CONFIGURATION
-- ============================================================
MERGE INTO ENV_CONFIG tgt
USING (
    SELECT * FROM VALUES
    ('DEV',  'SNOWFLAKE_LEARNING_DB', 'RAW_INGESTION', 'COMPUTE_WH', 4,  10.00, FALSE, TRUE),
    ('QA',   'SNOWFLAKE_LEARNING_DB', 'RAW_INGESTION', 'COMPUTE_WH', 4,  5.00,  TRUE,  TRUE),
    ('PROD', 'SNOWFLAKE_LEARNING_DB', 'RAW_INGESTION', 'COMPUTE_WH', 8,  2.00,  TRUE,  TRUE)
) AS src(environment, source_database, source_schema, warehouse_name, max_parallel_steps, dq_reject_threshold, enable_notifications, is_active)
ON tgt.environment = src.environment
WHEN MATCHED THEN UPDATE SET
    source_database = src.source_database,
    source_schema = src.source_schema,
    warehouse_name = src.warehouse_name,
    max_parallel_steps = src.max_parallel_steps,
    dq_reject_threshold = src.dq_reject_threshold,
    enable_notifications = src.enable_notifications
WHEN NOT MATCHED THEN INSERT VALUES
    (src.environment, src.source_database, src.source_schema, src.warehouse_name, src.max_parallel_steps, src.dq_reject_threshold, src.enable_notifications, src.is_active);

-- ============================================================
-- NOTIFICATION CONFIGURATION
-- ============================================================
MERGE INTO NOTIFICATION_CONFIG tgt
USING (
    SELECT * FROM VALUES
    ('EMAIL', 'RUN_START',    'data-engineering@company.com', 'P360 Package Run Started - {ENV}',     'Package: {PKG_NAME}\nRun ID: {RUN_ID}\nStarted: {START_TIME}\nMode: {RUN_MODE}', TRUE, 'P360_EMAIL_INT'),
    ('EMAIL', 'RUN_COMPLETE', 'data-engineering@company.com', 'P360 Package Run Completed - {ENV}',   'Package: {PKG_NAME}\nRun ID: {RUN_ID}\nDuration: {DURATION}\nStatus: SUCCESS\nRows Processed: {TOTAL_ROWS}', TRUE, 'P360_EMAIL_INT'),
    ('EMAIL', 'RUN_FAILURE',  'data-engineering@company.com;on-call@company.com', 'ALERT: P360 Package FAILED - {ENV}', 'Package: {PKG_NAME}\nRun ID: {RUN_ID}\nFailed Step: {FAILED_STEP}\nError: {ERROR_MSG}\nAction Required: Review and restart', TRUE, 'P360_EMAIL_INT'),
    ('EMAIL', 'DQ_THRESHOLD', 'data-quality@company.com',     'P360 DQ Threshold Exceeded - {ENV}',   'Source: {SOURCE_TABLE}\nReject Rate: {REJECT_PCT}%\nThreshold: {THRESHOLD}%\nReject Count: {REJECT_COUNT}', TRUE, 'P360_EMAIL_INT'),
    ('EMAIL', 'STEP_FAILURE', 'data-engineering@company.com', 'P360 Step Failed (Retrying) - {ENV}',  'Step: {STEP_NAME}\nAttempt: {ATTEMPT}/{MAX_RETRY}\nError: {ERROR_MSG}', TRUE, 'P360_EMAIL_INT')
) AS src(notification_type, event_type, recipients, subject_template, body_template, is_active, integration_name)
ON tgt.notification_type = src.notification_type AND tgt.event_type = src.event_type
WHEN MATCHED THEN UPDATE SET
    recipients = src.recipients,
    subject_template = src.subject_template,
    body_template = src.body_template
WHEN NOT MATCHED THEN INSERT
    (notification_type, event_type, recipients, subject_template, body_template, is_active, integration_name)
VALUES
    (src.notification_type, src.event_type, src.recipients, src.subject_template, src.body_template, src.is_active, src.integration_name);
