-- Core generic DQ engine procedure that evaluates rules from DQ_FEED config
-- Co-authored with CoCo
/*=============================================================================
  CLINICIAN-360-DQ-IMPLEMENTATION
  01_FRAMEWORK/004_dq_engine_procedure.sql
  
  Purpose: Generic DQ engine that reads DQ_FEED + DQ_RULE configuration and
           executes data quality checks dynamically against any table/layer.
           Supports SIMPLE, MULTIPLE, COMPLEX, and SQL FEED rule categories.
=============================================================================*/

USE DATABASE P360_DQ;
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
    v_dq_end_ts := CURRENT_TIMESTAMP();

    -- Determine schema from layer
    IF (:P_LAYER = 'BRONZE') THEN
        v_schema := 'BRONZE';
    ELSEIF (:P_LAYER = 'SILVER') THEN
        v_schema := 'SILVER';
    ELSE
        v_schema := 'GOLD';
    END IF;

    -- Get last DQ end timestamp for incremental processing
    SELECT COALESCE(MAX(DQ_END_TS), '1900-01-01'::TIMESTAMP_NTZ) INTO v_dq_start_ts
    FROM P360_DQ.AUDIT.DQ_LOG
    WHERE TABLE_NM = :P_TABLE_NM AND LAYER = :P_LAYER;

    -- Get total count of records to evaluate (DQ_STATUS IS NULL = new/updated)
    v_dyn_sql := 'SELECT COUNT(*) FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' WHERE DQ_STATUS IS NULL';
    EXECUTE IMMEDIATE :v_dyn_sql;
    LET rs1 RESULTSET := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    LET cur1 CURSOR FOR rs1;
    FOR rec1 IN cur1 DO
        v_overall_count := rec1.$1;
    END FOR;

    IF (:v_overall_count = 0) THEN
        -- No records to evaluate
        INSERT INTO P360_DQ.AUDIT.DQ_LOG (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
        VALUES (:P_DQ_BATCH_ID, :P_LAYER, NULL, :P_TABLE_NM, NULL, :v_dq_start_ts, :v_dq_end_ts, 0, 0, 'Success', CURRENT_TIMESTAMP());
        RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'table', :P_TABLE_NM, 'total', 0, 'failed', 0, 'threshold_exceeded', FALSE);
    END IF;

    -- Process each active feed for this table+layer
    LET v_feeds RESULTSET := (
        SELECT f.FEED_ID, f.RULE_ID, f.DQ_RULE_INPUT, f.RECORD_KEY_NM,
               f.INCREMENTAL_DATE_COLUMN, f.CRITICALITY_IND, f.DOMAIN,
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
        v_record_key_nm := feed.RECORD_KEY_NM;
        v_incr_col := feed.INCREMENTAL_DATE_COLUMN;
        v_criticality := feed.CRITICALITY_IND;
        v_domain := feed.DOMAIN;
        v_rule_exp := feed.RULE_EXP;
        v_rule_category := feed.RULE_CATEGORY;
        v_rule_code := feed.RULE_CODE;

        BEGIN
            -- For SIMPLE rules: evaluate expression per record
            IF (:v_rule_category = 'SIMPLE') THEN
                -- Build dynamic SQL to insert failing records into DQ_RESULT
                v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                    'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                    :v_rule_id || ', ' || :v_feed_id || ', ' ||
                    'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                    'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                    '''FAIL'', CURRENT_USER() ' ||
                    'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                    'WHERE DQ_STATUS IS NULL AND (' ||
                    'TRIM(COALESCE(CAST(' || :v_dq_rule_input || ' AS VARCHAR), '''')) = '''')';

                -- Adjust for specific rule types
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
                        'WHERE DQ_STATUS IS NULL AND LENGTH(TRIM(COALESCE(CAST(' || :v_dq_rule_input || ' AS VARCHAR), ''''))) <> 2';
                ELSEIF (:v_rule_code = 'GN_Length9') THEN
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND LENGTH(TRIM(COALESCE(CAST(' || :v_dq_rule_input || ' AS VARCHAR), ''''))) <> 9';
                ELSEIF (:v_rule_code = 'GN_Length10') THEN
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND LENGTH(TRIM(COALESCE(CAST(' || :v_dq_rule_input || ' AS VARCHAR), ''''))) <> 10';
                ELSEIF (:v_rule_code = 'GN_FormatTIN') THEN
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND NOT (SUBSTR(CAST(' || :v_dq_rule_input || ' AS VARCHAR),4,1) = ''-'' AND SUBSTR(CAST(' || :v_dq_rule_input || ' AS VARCHAR),7,1) = ''-'' AND LENGTH(REPLACE(CAST(' || :v_dq_rule_input || ' AS VARCHAR),''-'','''')) = 9)';
                ELSEIF (:v_rule_code = 'GN_UpperCase') THEN
                    v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                        'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                        :v_rule_id || ', ' || :v_feed_id || ', ' ||
                        'CAST(' || :v_record_key_nm || ' AS VARCHAR), ' ||
                        'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                        '''FAIL'', CURRENT_USER() ' ||
                        'FROM P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' ' ||
                        'WHERE DQ_STATUS IS NULL AND ' || :v_dq_rule_input || ' IS NOT NULL AND ' || :v_dq_rule_input || ' <> UPPER(' || :v_dq_rule_input || ')';
                END IF;

                EXECUTE IMMEDIATE :v_dyn_sql;
            END IF;
        EXCEPTION
            WHEN OTHER THEN
                v_err_msg := SQLERRM;
                INSERT INTO P360_DQ.AUDIT.DQ_LOG (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, ERROR_MESSAGE, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
                VALUES (:P_DQ_BATCH_ID, :P_LAYER, :v_domain, :P_TABLE_NM, :v_feed_id, :v_dq_start_ts, :v_dq_end_ts, :v_err_msg, 0, 0, 'Fail', CURRENT_TIMESTAMP());
        END;
    END FOR;

    -- Count total failures for this batch
    SELECT COUNT(*) INTO v_fail_count
    FROM P360_DQ.AUDIT.DQ_RESULT
    WHERE DQ_BATCH_ID = :P_DQ_BATCH_ID AND TABLE_NM = :P_TABLE_NM AND RESULT = 'FAIL';

    -- Get distinct failing record keys (for DQ_STATUS update)
    -- Update DQ_STATUS on source table: records with failures get FAIL or PASS-SOFT
    -- Critical failures → FAIL; Non-critical only → PASS-SOFT; No failures → PASS
    v_dyn_sql := 'UPDATE P360_DQ.' || :v_schema || '.' || :P_TABLE_NM || ' t ' ||
        'SET DQ_STATUS = CASE WHEN EXISTS (SELECT 1 FROM P360_DQ.AUDIT.DQ_RESULT r JOIN P360_DQ.CONFIG.DQ_FEED f ON r.FEED_ID = f.FEED_ID WHERE r.DQ_BATCH_ID = ''' || :P_DQ_BATCH_ID || ''' AND r.TABLE_NM = ''' || :P_TABLE_NM || ''' AND r.RECORD_KEY = CAST(t.' || v_record_key_nm || ' AS VARCHAR) AND f.CRITICALITY_IND = ''Y'') THEN ''FAIL'' ' ||
        'WHEN EXISTS (SELECT 1 FROM P360_DQ.AUDIT.DQ_RESULT r JOIN P360_DQ.CONFIG.DQ_FEED f ON r.FEED_ID = f.FEED_ID WHERE r.DQ_BATCH_ID = ''' || :P_DQ_BATCH_ID || ''' AND r.TABLE_NM = ''' || :P_TABLE_NM || ''' AND r.RECORD_KEY = CAST(t.' || v_record_key_nm || ' AS VARCHAR) AND f.CRITICALITY_IND = ''N'') THEN ''PASS-SOFT'' ' ||
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
        VALUES (:P_DQ_BATCH_ID, :P_LAYER, NULL, :P_TABLE_NM, NULL, :v_dq_start_ts, :v_dq_end_ts, :v_err_msg, 0, 0, 'Fail', CURRENT_TIMESTAMP());
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'table', :P_TABLE_NM, 'error', :v_err_msg);
END;
$$;
