-- DQ Engine fix and Silver layer rule additions for Clinician-360 framework
-- Co-authored with CoCo

USE DATABASE P360_DQ;

/*=============================================================================
  FIX 1: Add new DQ rules - GN_InList for specific value validation
         and GN_Duplicate handling in the engine
=============================================================================*/

-- Add GN_InList rule (validates column value is in a specified list)
INSERT INTO CONFIG.DQ_RULE (CATEGORY_ID, RULE_CODE, RULE_DESC, RULE_EXP, RULE_CATEGORY)
SELECT 6, 'GN_InList', 'Validate value is in allowed list',
       'CASE WHEN ${INPUT1} NOT IN (${INPUT2}) THEN ''FAIL'' ELSE ''PASS'' END',
       'SIMPLE'
WHERE NOT EXISTS (SELECT 1 FROM CONFIG.DQ_RULE WHERE RULE_CODE = 'GN_InList');

-- Capture the new RULE_ID for GN_InList
SET v_inlist_rule_id = (SELECT RULE_ID FROM CONFIG.DQ_RULE WHERE RULE_CODE = 'GN_InList');

/*=============================================================================
  FIX 2: Add Bronze DQ_FEED entry for CREDENTIAL validation using GN_InList
=============================================================================*/

INSERT INTO CONFIG.DQ_FEED (LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM,
    INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, DQ_RULE_INPUT_WHERE_COL,
    CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP)
SELECT 'BRONZE', 'PROVIDERS', $v_inlist_rule_id, 'STG_NPI_REGISTRY', 'NPI_SK',
       'LOAD_DT', 'CREDENTIAL', '''MD'',''DO'',''NP'',''PA'',''RN'',''APRN'',''DPM'',''DDS'',''PhD'',''PharmD'',''OD'',''DC''',
       'Y', 'Y', 'GROUP_A'
WHERE NOT EXISTS (
    SELECT 1 FROM CONFIG.DQ_FEED
    WHERE TABLE_NM = 'STG_NPI_REGISTRY' AND DQ_RULE_INPUT = 'CREDENTIAL'
      AND LAYER = 'BRONZE'
);

/*=============================================================================
  FIX 3: Add richer Silver layer DQ rules
         - Credential validation (specific values)
         - Gender validation
         - Phone format
         - Deduplication check on PROVIDER_NPI
=============================================================================*/

-- Credential must be in valid list (Silver)
INSERT INTO CONFIG.DQ_FEED (LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM,
    INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, DQ_RULE_INPUT_WHERE_COL,
    CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP)
SELECT 'SILVER', 'PROVIDERS', $v_inlist_rule_id, 'DIM_PROVIDER', 'PROVIDER_SK',
       'LOAD_DT', 'CREDENTIAL', '''MD'',''DO'',''NP'',''PA'',''RN'',''APRN'',''DPM'',''DDS'',''PhD'',''PharmD'',''OD'',''DC''',
       'Y', 'Y', 'GROUP_A'
WHERE NOT EXISTS (
    SELECT 1 FROM CONFIG.DQ_FEED
    WHERE TABLE_NM = 'DIM_PROVIDER' AND DQ_RULE_INPUT = 'CREDENTIAL'
      AND LAYER = 'SILVER'
);

-- Gender must be M or F (Silver)
INSERT INTO CONFIG.DQ_FEED (LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM,
    INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, DQ_RULE_INPUT_WHERE_COL,
    CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP)
SELECT 'SILVER', 'PROVIDERS', $v_inlist_rule_id, 'DIM_PROVIDER', 'PROVIDER_SK',
       'LOAD_DT', 'GENDER', '''M'',''F''',
       'N', 'Y', 'GROUP_A'
WHERE NOT EXISTS (
    SELECT 1 FROM CONFIG.DQ_FEED
    WHERE TABLE_NM = 'DIM_PROVIDER' AND DQ_RULE_INPUT = 'GENDER'
      AND LAYER = 'SILVER'
);

-- Provider NPI must not be duplicate (Silver)
INSERT INTO CONFIG.DQ_FEED (LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM,
    INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP)
SELECT 'SILVER', 'PROVIDERS', 1, 'DIM_PROVIDER', 'PROVIDER_SK',
       'LOAD_DT', 'PROVIDER_NPI', 'Y', 'Y', 'GROUP_A'
WHERE NOT EXISTS (
    SELECT 1 FROM CONFIG.DQ_FEED
    WHERE TABLE_NM = 'DIM_PROVIDER' AND RULE_ID = 1
      AND LAYER = 'SILVER' AND DQ_RULE_INPUT = 'PROVIDER_NPI'
);

-- Provider phone not null (Silver - non-critical)
INSERT INTO CONFIG.DQ_FEED (LAYER, DOMAIN, RULE_ID, TABLE_NM, RECORD_KEY_NM,
    INCREMENTAL_DATE_COLUMN, DQ_RULE_INPUT, CRITICALITY_IND, ACTIVE_IND, EXECUTION_GROUP)
SELECT 'SILVER', 'PROVIDERS', 2, 'DIM_PROVIDER', 'PROVIDER_SK',
       'LOAD_DT', 'PHONE', 'N', 'Y', 'GROUP_A'
WHERE NOT EXISTS (
    SELECT 1 FROM CONFIG.DQ_FEED
    WHERE TABLE_NM = 'DIM_PROVIDER' AND RULE_ID = 2 AND DQ_RULE_INPUT = 'PHONE'
      AND LAYER = 'SILVER'
);

/*=============================================================================
  FIX 4: Recreate DQ Engine procedure with full rule support
         - Handles SIMPLE rules: GN_NotNull, GN_Length2/9/10, GN_FormatTIN,
           GN_UpperCase, GN_Timeliness, GN_InList
         - Handles COMPLEX rules: GN_Duplicate
         - Properly updates DQ_STATUS after checks complete
=============================================================================*/

USE SCHEMA CONFIG;

CREATE OR REPLACE PROCEDURE CONFIG.SP_RUN_DQ_CHECK(
    P_RUN_ID        VARCHAR,
    P_TABLE_NM      VARCHAR,
    P_LAYER         VARCHAR,
    P_DQ_BATCH_ID   VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_feed_id NUMBER;
    v_rule_id NUMBER;
    v_rule_exp STRING;
    v_rule_category STRING;
    v_rule_code STRING;
    v_dq_rule_input STRING;
    v_dq_rule_input_where STRING;
    v_record_key_nm STRING;
    v_incr_col STRING;
    v_criticality STRING;
    v_domain STRING;
    v_overall_count NUMBER DEFAULT 0;
    v_fail_count NUMBER DEFAULT 0;
    v_dq_start_ts TIMESTAMP_NTZ;
    v_dq_end_ts TIMESTAMP_NTZ;
    v_dyn_sql STRING;
    v_err_msg STRING;
    v_schema STRING;
BEGIN
    v_dq_start_ts := CURRENT_TIMESTAMP();

    IF (:P_LAYER = 'BRONZE') THEN
        v_schema := 'BRONZE';
    ELSEIF (:P_LAYER = 'SILVER') THEN
        v_schema := 'SILVER';
    ELSE
        v_schema := 'GOLD';
    END IF;

    -- Get total count of records to evaluate (DQ_STATUS IS NULL = new/unprocessed)
    v_dyn_sql := 'SELECT COUNT(*) FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' WHERE DQ_STATUS IS NULL';
    EXECUTE IMMEDIATE :v_dyn_sql;
    LET rs1 RESULTSET := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    LET cur1 CURSOR FOR rs1;
    FOR rec1 IN cur1 DO
        v_overall_count := rec1.$1;
    END FOR;

    IF (:v_overall_count = 0) THEN
        INSERT INTO P360_DQ.AUDIT.DQ_LOG (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
        VALUES (:P_DQ_BATCH_ID, :P_LAYER, NULL, :P_TABLE_NM, NULL, :v_dq_start_ts, CURRENT_TIMESTAMP(), 0, 0, 'Success', CURRENT_TIMESTAMP());
        RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'table', :P_TABLE_NM, 'total', 0, 'failed', 0, 'threshold_exceeded', FALSE);
    END IF;

    -- Process each active feed for this table+layer
    LET v_feeds RESULTSET := (
        SELECT f.FEED_ID, f.RULE_ID, f.DQ_RULE_INPUT, f.DQ_RULE_INPUT_WHERE_COL,
               f.RECORD_KEY_NM, f.INCREMENTAL_DATE_COLUMN, f.CRITICALITY_IND, f.DOMAIN,
               r.RULE_EXP, r.RULE_CATEGORY, r.RULE_CODE
        FROM P360_DQ.CONFIG.DQ_FEED f
        JOIN P360_DQ.CONFIG.DQ_RULE r ON f.RULE_ID = r.RULE_ID
        WHERE f.TABLE_NM = :P_TABLE_NM
          AND f.LAYER = :P_LAYER
          AND f.ACTIVE_IND = 'Y'
        ORDER BY f.FEED_ID
    );
    LET cur_feeds CURSOR FOR v_feeds;

    FOR feed IN cur_feeds DO
        v_feed_id := feed.FEED_ID;
        v_rule_id := feed.RULE_ID;
        v_dq_rule_input := feed.DQ_RULE_INPUT;
        v_dq_rule_input_where := feed.DQ_RULE_INPUT_WHERE_COL;
        v_record_key_nm := feed.RECORD_KEY_NM;
        v_incr_col := feed.INCREMENTAL_DATE_COLUMN;
        v_criticality := feed.CRITICALITY_IND;
        v_domain := feed.DOMAIN;
        v_rule_exp := feed.RULE_EXP;
        v_rule_category := feed.RULE_CATEGORY;
        v_rule_code := feed.RULE_CODE;

        BEGIN
            -- ====== SIMPLE RULES ======
            IF (:v_rule_category = 'SIMPLE') THEN

                IF (:v_rule_code = 'GN_NotNull') THEN
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND TRIM(COALESCE(CAST(' || :v_dq_rule_input || ' AS VARCHAR), '''')) = ''''';

                ELSEIF (:v_rule_code = 'GN_Length2') THEN
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND ' || :v_dq_rule_input || ' IS NOT NULL AND LENGTH(TRIM(CAST(' || :v_dq_rule_input || ' AS VARCHAR))) <> 2';

                ELSEIF (:v_rule_code = 'GN_Length9') THEN
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND ' || :v_dq_rule_input || ' IS NOT NULL AND LENGTH(TRIM(CAST(' || :v_dq_rule_input || ' AS VARCHAR))) <> 9';

                ELSEIF (:v_rule_code = 'GN_Length10') THEN
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND ' || :v_dq_rule_input || ' IS NOT NULL AND LENGTH(TRIM(CAST(' || :v_dq_rule_input || ' AS VARCHAR))) <> 10';

                ELSEIF (:v_rule_code = 'GN_FormatTIN') THEN
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND ' || :v_dq_rule_input || ' IS NOT NULL ' ||
                        'AND NOT (SUBSTR(CAST(' || :v_dq_rule_input || ' AS VARCHAR),4,1) = ''-'' AND SUBSTR(CAST(' || :v_dq_rule_input || ' AS VARCHAR),7,1) = ''-'' AND LENGTH(REPLACE(CAST(' || :v_dq_rule_input || ' AS VARCHAR),''-'','''')) = 9)';

                ELSEIF (:v_rule_code = 'GN_UpperCase') THEN
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND ' || :v_dq_rule_input || ' IS NOT NULL AND ' || :v_dq_rule_input || ' <> UPPER(' || :v_dq_rule_input || ')';

                ELSEIF (:v_rule_code = 'GN_Timeliness') THEN
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND ' || :v_dq_rule_input || ' IS NOT NULL AND DATEDIFF(''DAY'', ' || :v_dq_rule_input || ', CURRENT_DATE()) > 365';

                ELSEIF (:v_rule_code = 'GN_InList') THEN
                    -- DQ_RULE_INPUT = column name, DQ_RULE_INPUT_WHERE_COL = comma-separated quoted values
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND ' || :v_dq_rule_input || ' IS NOT NULL ' ||
                        'AND UPPER(TRIM(' || :v_dq_rule_input || ')) NOT IN (' || :v_dq_rule_input_where || ')';

                ELSE
                    -- Unknown SIMPLE rule - skip
                    v_dyn_sql := NULL;
                END IF;

                IF (v_dyn_sql IS NOT NULL) THEN
                    EXECUTE IMMEDIATE :v_dyn_sql;
                END IF;

            -- ====== COMPLEX RULES ======
            ELSEIF (:v_rule_category = 'COMPLEX') THEN

                IF (:v_rule_code = 'GN_Duplicate') THEN
                    -- Find duplicates on the DQ_RULE_INPUT column; flag all but first occurrence
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY ' || :v_dq_rule_input || ' ORDER BY ' || :v_incr_col || ' DESC) AS rn ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' WHERE DQ_STATUS IS NULL) ' ||
                        'WHERE rn > 1';
                    EXECUTE IMMEDIATE :v_dyn_sql;

                END IF;
                -- GN_LOOKUP and GN_RefIntegrity would use JOIN columns - skip if NULL

            END IF;

        EXCEPTION
            WHEN OTHER THEN
                v_err_msg := SQLERRM;
                INSERT INTO P360_DQ.AUDIT.DQ_LOG (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, ERROR_MESSAGE, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
                VALUES (:P_DQ_BATCH_ID, :P_LAYER, :v_domain, :P_TABLE_NM, :v_feed_id, :v_dq_start_ts, CURRENT_TIMESTAMP(), :v_err_msg, 0, 0, 'Fail', CURRENT_TIMESTAMP());
        END;
    END FOR;

    -- Count total failures for this batch
    SELECT COUNT(*) INTO v_fail_count
    FROM P360_DQ.AUDIT.DQ_RESULT
    WHERE DQ_BATCH_ID = :P_DQ_BATCH_ID AND TABLE_NM = :P_TABLE_NM AND RESULT = 'FAIL';

    v_dq_end_ts := CURRENT_TIMESTAMP();

    -- Update DQ_STATUS on source table:
    --   Records with critical failures → FAIL
    --   Records with non-critical failures only → PASS-SOFT
    --   Records with no failures → PASS
    v_dyn_sql := 'UPDATE P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' t ' ||
        'SET DQ_STATUS = CASE ' ||
        'WHEN EXISTS (SELECT 1 FROM P360_DQ.AUDIT.DQ_RESULT r JOIN P360_DQ.CONFIG.DQ_FEED f ON r.FEED_ID = f.FEED_ID ' ||
        'WHERE r.DQ_BATCH_ID = ''' || :P_DQ_BATCH_ID || ''' AND r.TABLE_NM = ''' || :P_TABLE_NM || ''' ' ||
        'AND r.RECORD_KEY = CAST(t.' || :v_record_key_nm || ' AS VARCHAR) AND f.CRITICALITY_IND = ''Y'') THEN ''FAIL'' ' ||
        'WHEN EXISTS (SELECT 1 FROM P360_DQ.AUDIT.DQ_RESULT r JOIN P360_DQ.CONFIG.DQ_FEED f ON r.FEED_ID = f.FEED_ID ' ||
        'WHERE r.DQ_BATCH_ID = ''' || :P_DQ_BATCH_ID || ''' AND r.TABLE_NM = ''' || :P_TABLE_NM || ''' ' ||
        'AND r.RECORD_KEY = CAST(t.' || :v_record_key_nm || ' AS VARCHAR) AND f.CRITICALITY_IND = ''N'') THEN ''PASS-SOFT'' ' ||
        'ELSE ''PASS'' END ' ||
        'WHERE t.DQ_STATUS IS NULL';
    EXECUTE IMMEDIATE :v_dyn_sql;

    -- Log to DQ_LOG
    INSERT INTO P360_DQ.AUDIT.DQ_LOG (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
    VALUES (:P_DQ_BATCH_ID, :P_LAYER, :v_domain, :P_TABLE_NM, NULL, :v_dq_start_ts, :v_dq_end_ts, :v_overall_count, :v_fail_count, 'Success', CURRENT_TIMESTAMP());

    -- Archive to DQ_LOG_HISTORY
    INSERT INTO P360_DQ.AUDIT.DQ_LOG_HISTORY (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
    VALUES (:P_DQ_BATCH_ID, :P_LAYER, :v_domain, :P_TABLE_NM, NULL, :v_dq_start_ts, :v_dq_end_ts, :v_overall_count, :v_fail_count, 'Success', CURRENT_TIMESTAMP());

    -- Check threshold
    LET v_threshold_exceeded BOOLEAN := FALSE;
    IF (:v_overall_count > 0) THEN
        CALL P360_DQ.CONFIG.SP_CHECK_DQ_THRESHOLD(:P_RUN_ID, NULL, :P_TABLE_NM, :v_overall_count, :v_fail_count);
        v_threshold_exceeded := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    END IF;

    RETURN OBJECT_CONSTRUCT(
        'status', CASE WHEN v_threshold_exceeded THEN 'THRESHOLD_EXCEEDED' ELSE 'COMPLETED' END,
        'table', :P_TABLE_NM,
        'layer', :P_LAYER,
        'total_records', :v_overall_count,
        'failed_records', :v_fail_count,
        'fail_pct', CASE WHEN :v_overall_count > 0 THEN ROUND((:v_fail_count::FLOAT / :v_overall_count) * 100, 2) ELSE 0 END,
        'threshold_exceeded', v_threshold_exceeded
    );

EXCEPTION
    WHEN OTHER THEN
        v_err_msg := SQLERRM;
        INSERT INTO P360_DQ.AUDIT.DQ_LOG (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, ERROR_MESSAGE, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
        VALUES (:P_DQ_BATCH_ID, :P_LAYER, NULL, :P_TABLE_NM, NULL, :v_dq_start_ts, CURRENT_TIMESTAMP(), :v_err_msg, 0, 0, 'Fail', CURRENT_TIMESTAMP());
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'table', :P_TABLE_NM, 'error', :v_err_msg);
END;
$$;

/*=============================================================================
  FIX 5: Reset Bronze DQ_STATUS and re-run full pipeline
=============================================================================*/

-- Reset DQ_STATUS so engine can re-evaluate
UPDATE P360_DQ.BRONZE.STG_NPI_REGISTRY SET DQ_STATUS = NULL;
UPDATE P360_DQ.BRONZE.STG_SPECIALTY_TYPE SET DQ_STATUS = NULL;

-- Clear previous DQ results for clean re-run
TRUNCATE TABLE P360_DQ.AUDIT.DQ_RESULT;
TRUNCATE TABLE P360_DQ.AUDIT.DQ_LOG;

-- Run full pipeline
CALL P360_DQ.ORCHESTRATION.SP_RUN_PACKAGE('FULL');

/*=============================================================================
  VALIDATION QUERIES (run after pipeline completes)
=============================================================================*/

-- Check DQ_STATUS populated in Bronze
SELECT DQ_STATUS, COUNT(*) AS cnt FROM P360_DQ.BRONZE.STG_NPI_REGISTRY GROUP BY DQ_STATUS;
SELECT DQ_STATUS, COUNT(*) AS cnt FROM P360_DQ.BRONZE.STG_SPECIALTY_TYPE GROUP BY DQ_STATUS;

-- Check DQ_RESULT has entries
SELECT TABLE_NM, RULE_ID, RESULT, COUNT(*) FROM P360_DQ.AUDIT.DQ_RESULT GROUP BY TABLE_NM, RULE_ID, RESULT ORDER BY TABLE_NM, RULE_ID;

-- Check Silver DIM_PROVIDER is populated
SELECT COUNT(*) AS dim_provider_count FROM P360_DQ.SILVER.DIM_PROVIDER;
SELECT * FROM P360_DQ.SILVER.DIM_PROVIDER LIMIT 10;

-- Check DQ rules configuration
SELECT f.FEED_ID, f.LAYER, f.TABLE_NM, f.DQ_RULE_INPUT, f.DQ_RULE_INPUT_WHERE_COL, r.RULE_CODE, f.CRITICALITY_IND
FROM P360_DQ.CONFIG.DQ_FEED f
JOIN P360_DQ.CONFIG.DQ_RULE r ON f.RULE_ID = r.RULE_ID
WHERE f.ACTIVE_IND = 'Y'
ORDER BY f.LAYER, f.TABLE_NM, f.FEED_ID;
