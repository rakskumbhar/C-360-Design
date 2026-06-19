-- Configurable DQ engine using token-substituted RULE_EXP from DQ_RULE metadata
-- Co-authored with CoCo
/*=============================================================================
  CLINICIAN-360-DQ-IMPLEMENTATION
  01_FRAMEWORK/004_dq_engine_procedure.sql
  
  Purpose: Generic DQ engine that reads DQ_FEED + DQ_RULE configuration and
           dynamically builds SQL from RULE_EXP templates via token substitution.
           No hardcoded rule logic - adding a new rule only requires a config row.
           
  Design (reference architecture):
    SP_RUN_DQ_CHECK (= DQ_Run + DQ_Process_Failed_Record combined)
      1. Count source rows where DQ_STATUS IS NULL
      2. For SIMPLE rules: evaluate expression per-row, insert FAILs
      3. For COMPLEX rules: run resolved RULE_EXP with FROM/WHERE/QUALIFY
      4. Insert failures into DQ_RESULT
      5. MERGE DQ_STATUS back to source table (FAIL / PASS-SOFT / PASS)
      6. Log results to DQ_LOG and DQ_LOG_HISTORY
      
  Token Reference (used in DQ_RULE.RULE_EXP):
    ${INPUT1}     - DQ_FEED.DQ_RULE_INPUT (column name)
    ${INPUT2}     - DQ_FEED.DQ_RULE_INPUT_WHERE_COL (allowed values / param)
    ${INPUTN}     - DQ_FEED.DQ_RULE_INPUT (for partition-based rules)
    ${TABLE_NAME} - Fully qualified table: P360_DQ.<schema>.<table>
    ${JOINTBL1}   - P360_DQ.<schema>.<source table> (from DQ_FEED)
    ${JOINTBL2}   - DQ_FEED.DQ_RULE_INPUT_JOIN_TBL
    ${JOINCOL1}   - DQ_FEED.DQ_RULE_INPUT (source join column)
    ${JOINCOL2}   - DQ_FEED.DQ_RULE_INPUT_JOIN_COL
    ${WHERECOL1}  - DQ_FEED.DQ_RULE_INPUT_WHERE_COL
    ${INCREMENTAL_DATE_COLUMN} - filter: DQ_STATUS IS NULL
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
    v_schema            STRING;
    v_fq_table          STRING;
    v_overall_count     NUMBER DEFAULT 0;
    v_fail_count        NUMBER DEFAULT 0;
    v_dq_start_ts       TIMESTAMP_NTZ;
    v_dq_end_ts         TIMESTAMP_NTZ;
    v_dyn_sql           STRING;
    v_resolved_exp      STRING;
    v_err_msg           STRING;
    v_record_key_nm     STRING;
    v_threshold_exceeded BOOLEAN DEFAULT FALSE;
    -- Feed cursor variables
    v_feed_id           NUMBER;
    v_rule_id           NUMBER;
    v_dq_rule_input     STRING;
    v_feed_rec_key      STRING;
    v_incr_col          STRING;
    v_criticality       STRING;
    v_domain            STRING;
    v_join_tbl          STRING;
    v_join_col          STRING;
    v_where_col         STRING;
    v_rule_exp          STRING;
    v_rule_category     STRING;
    v_rule_code         STRING;
BEGIN
    v_dq_start_ts := CURRENT_TIMESTAMP();

    v_schema := CASE
        WHEN :P_LAYER = 'BRONZE' THEN 'BRONZE'
        WHEN :P_LAYER = 'SILVER' THEN 'SILVER'
        WHEN :P_LAYER = 'GOLD'   THEN 'GOLD'
        ELSE :P_LAYER
    END;
    v_fq_table := 'P360_DQ.' || :v_schema || '.' || :P_TABLE_NM;

    -- Step 1: Count source rows needing evaluation
    v_dyn_sql := 'SELECT COUNT(*) AS CNT FROM ' || :v_fq_table || ' WHERE DQ_STATUS IS NULL';
    LET rs_cnt RESULTSET := (EXECUTE IMMEDIATE :v_dyn_sql);
    LET cur_cnt CURSOR FOR rs_cnt;
    FOR r IN cur_cnt DO
        v_overall_count := r.CNT;
    END FOR;

    IF (:v_overall_count = 0) THEN
        INSERT INTO P360_DQ.AUDIT.DQ_LOG (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
        VALUES (:P_DQ_BATCH_ID, :P_LAYER, NULL, :P_TABLE_NM, NULL, :v_dq_start_ts, CURRENT_TIMESTAMP(), 0, 0, 'Success', CURRENT_TIMESTAMP());
        RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'table', :P_TABLE_NM, 'total', 0, 'failed', 0, 'threshold_exceeded', FALSE);
    END IF;

    -- Get RECORD_KEY_NM
    SELECT RECORD_KEY_NM INTO v_record_key_nm
    FROM P360_DQ.CONFIG.DQ_FEED
    WHERE TABLE_NM = :P_TABLE_NM AND LAYER = :P_LAYER AND ACTIVE_IND = 'Y'
    LIMIT 1;

    -- Step 2: Process each feed via token-substituted RULE_EXP
    LET v_feeds RESULTSET := (
        SELECT f.FEED_ID AS F_FEED_ID, f.RULE_ID AS F_RULE_ID,
               f.DQ_RULE_INPUT AS F_DQ_RULE_INPUT, f.RECORD_KEY_NM AS F_RECORD_KEY_NM,
               f.INCREMENTAL_DATE_COLUMN AS F_INCR_COL, f.CRITICALITY_IND AS F_CRIT,
               f.DOMAIN AS F_DOMAIN,
               f.DQ_RULE_INPUT_JOIN_TBL AS F_JOIN_TBL,
               f.DQ_RULE_INPUT_JOIN_COL AS F_JOIN_COL,
               f.DQ_RULE_INPUT_WHERE_COL AS F_WHERE_COL,
               r.RULE_EXP AS R_RULE_EXP, r.RULE_CATEGORY AS R_RULE_CATEGORY,
               r.RULE_CODE AS R_RULE_CODE
        FROM P360_DQ.CONFIG.DQ_FEED f
        JOIN P360_DQ.CONFIG.DQ_RULE r ON f.RULE_ID = r.RULE_ID
        WHERE f.TABLE_NM = :P_TABLE_NM
          AND f.LAYER = :P_LAYER
          AND f.ACTIVE_IND = 'Y'
        ORDER BY f.FEED_ID
    );
    LET cur_feeds CURSOR FOR v_feeds;

    FOR feed IN cur_feeds DO
        BEGIN
            -- Assign cursor fields to local variables
            v_feed_id := feed.F_FEED_ID;
            v_rule_id := feed.F_RULE_ID;
            v_dq_rule_input := feed.F_DQ_RULE_INPUT;
            v_feed_rec_key := feed.F_RECORD_KEY_NM;
            v_incr_col := feed.F_INCR_COL;
            v_criticality := feed.F_CRIT;
            v_domain := feed.F_DOMAIN;
            v_join_tbl := feed.F_JOIN_TBL;
            v_join_col := feed.F_JOIN_COL;
            v_where_col := feed.F_WHERE_COL;
            v_rule_exp := feed.R_RULE_EXP;
            v_rule_category := feed.R_RULE_CATEGORY;
            v_rule_code := feed.R_RULE_CODE;

            -- Token substitution on RULE_EXP
            v_resolved_exp := :v_rule_exp;
            v_resolved_exp := REPLACE(:v_resolved_exp, '${INPUT1}', 'CAST(' || :v_dq_rule_input || ' AS VARCHAR)');
            v_resolved_exp := REPLACE(:v_resolved_exp, '${INPUT2}', COALESCE(:v_where_col, ''));
            v_resolved_exp := REPLACE(:v_resolved_exp, '${INPUTN}', :v_dq_rule_input);
            v_resolved_exp := REPLACE(:v_resolved_exp, '${TABLE_NAME}', :v_fq_table);
            v_resolved_exp := REPLACE(:v_resolved_exp, '${JOINTBL1}', :v_fq_table);
            v_resolved_exp := REPLACE(:v_resolved_exp, '${JOINTBL2}', COALESCE(:v_join_tbl, ''));
            v_resolved_exp := REPLACE(:v_resolved_exp, '${JOINCOL1}', :v_dq_rule_input);
            v_resolved_exp := REPLACE(:v_resolved_exp, '${JOINCOL2}', COALESCE(:v_join_col, ''));
            v_resolved_exp := REPLACE(:v_resolved_exp, '${WHERECOL1}', COALESCE(:v_where_col, ''));
            v_resolved_exp := REPLACE(:v_resolved_exp, '${INCREMENTAL_DATE_COLUMN}', 'DQ_STATUS IS NULL');

            IF (:v_rule_category = 'SIMPLE') THEN
                v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT ' ||
                    '(DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                    'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                    :v_rule_id || ', ' || :v_feed_id || ', ' ||
                    'CAST(' || :v_feed_rec_key || ' AS VARCHAR), ' ||
                    'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                    '''' || CASE WHEN :v_criticality = 'Y' THEN 'FAIL' ELSE 'PASS-SOFT' END || ''', CURRENT_USER() ' ||
                    'FROM ' || :v_fq_table || ' ' ||
                    'WHERE DQ_STATUS IS NULL AND (' || :v_resolved_exp || ') = ''FAIL''';

            ELSEIF (:v_rule_category = 'COMPLEX') THEN
                -- COMPLEX: Duplicate detection via QUALIFY ROW_NUMBER
                v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT ' ||
                    '(DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                    'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                    :v_rule_id || ', ' || :v_feed_id || ', ' ||
                    'CAST(a.' || :v_feed_rec_key || ' AS VARCHAR), ' ||
                    'CAST(a.' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                    '''' || CASE WHEN :v_criticality = 'Y' THEN 'FAIL' ELSE 'PASS-SOFT' END || ''', CURRENT_USER() ' ||
                    'FROM ' || :v_fq_table || ' a WHERE DQ_STATUS IS NULL QUALIFY ' ||
                    '(ROW_NUMBER() OVER(PARTITION BY ' || :v_dq_rule_input || ' ORDER BY ' || :v_incr_col || ' DESC)) > 1';

            ELSEIF (:v_rule_category = 'SQL_FEED') THEN
                v_dyn_sql := 'INSERT INTO P360_DQ.AUDIT.DQ_RESULT ' ||
                    '(DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, RULE_ID, FEED_ID, RECORD_KEY, RECORD_VALUE, RESULT, RECORD_INS_BY) ' ||
                    'SELECT ''' || :P_DQ_BATCH_ID || ''', ''' || :P_LAYER || ''', ''' || :v_domain || ''', ''' || :P_TABLE_NM || ''', ' ||
                    :v_rule_id || ', ' || :v_feed_id || ', ' ||
                    'CAST(' || :v_feed_rec_key || ' AS VARCHAR), ' ||
                    'CAST(' || :v_dq_rule_input || ' AS VARCHAR), ' ||
                    '''' || CASE WHEN :v_criticality = 'Y' THEN 'FAIL' ELSE 'PASS-SOFT' END || ''', CURRENT_USER() ' ||
                    'FROM (' || :v_resolved_exp || ') sub ' ||
                    'WHERE sub.RESULT = ''FAIL''';

            END IF;

            EXECUTE IMMEDIATE :v_dyn_sql;

        EXCEPTION
            WHEN OTHER THEN
                v_err_msg := SQLERRM;
                INSERT INTO P360_DQ.AUDIT.DQ_LOG
                    (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, ERROR_MESSAGE, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
                VALUES (:P_DQ_BATCH_ID, :P_LAYER, :v_domain, :P_TABLE_NM, :v_feed_id,
                        :v_dq_start_ts, CURRENT_TIMESTAMP(), :v_err_msg, 0, 0, 'Fail', CURRENT_TIMESTAMP());
        END;
    END FOR;

    -- Step 3: Count distinct CRITICAL failures (RESULT='FAIL') for threshold check
    SELECT COUNT(DISTINCT RECORD_KEY) INTO v_fail_count
    FROM P360_DQ.AUDIT.DQ_RESULT
    WHERE DQ_BATCH_ID = :P_DQ_BATCH_ID AND TABLE_NM = :P_TABLE_NM AND RESULT = 'FAIL';

    -- Step 4: MERGE DQ_STATUS back to source table
    -- Uses RESULT from DQ_RESULT directly: worst status wins (FAIL > PASS-SOFT)
    v_dyn_sql := 'MERGE INTO ' || :v_fq_table || ' tgt USING (' ||
        'SELECT RECORD_KEY, ' ||
        'CASE WHEN MAX(CASE WHEN RESULT = ''FAIL'' THEN 1 ELSE 0 END) > 0 THEN ''FAIL'' ' ||
        'ELSE ''PASS-SOFT'' END AS COMPUTED_STATUS ' ||
        'FROM P360_DQ.AUDIT.DQ_RESULT ' ||
        'WHERE DQ_BATCH_ID = ''' || :P_DQ_BATCH_ID || ''' AND TABLE_NM = ''' || :P_TABLE_NM || ''' ' ||
        'GROUP BY RECORD_KEY' ||
        ') src ON CAST(tgt.' || :v_record_key_nm || ' AS VARCHAR) = src.RECORD_KEY ' ||
        'WHEN MATCHED AND tgt.DQ_STATUS IS NULL THEN UPDATE SET DQ_STATUS = src.COMPUTED_STATUS';
    EXECUTE IMMEDIATE :v_dyn_sql;

    -- Remaining NULL records = PASS (no failures found)
    v_dyn_sql := 'UPDATE ' || :v_fq_table || ' SET DQ_STATUS = ''PASS'' WHERE DQ_STATUS IS NULL';
    EXECUTE IMMEDIATE :v_dyn_sql;

    -- Step 5: Log results
    v_dq_end_ts := CURRENT_TIMESTAMP();

    INSERT INTO P360_DQ.AUDIT.DQ_LOG
        (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
    VALUES (:P_DQ_BATCH_ID, :P_LAYER, NULL, :P_TABLE_NM, NULL, :v_dq_start_ts, :v_dq_end_ts, :v_overall_count, :v_fail_count, 'Success', CURRENT_TIMESTAMP());

    INSERT INTO P360_DQ.AUDIT.DQ_LOG_HISTORY
        (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
    VALUES (:P_DQ_BATCH_ID, :P_LAYER, NULL, :P_TABLE_NM, NULL, :v_dq_start_ts, :v_dq_end_ts, :v_overall_count, :v_fail_count, 'Success', CURRENT_TIMESTAMP());

    -- Step 6: Check threshold
    IF (:v_overall_count > 0) THEN
        CALL P360_DQ.CONFIG.SP_CHECK_DQ_THRESHOLD(:P_RUN_ID, NULL, :P_TABLE_NM, :v_overall_count, :v_fail_count);
        v_threshold_exceeded := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    END IF;

    RETURN OBJECT_CONSTRUCT(
        'status', CASE WHEN :v_threshold_exceeded THEN 'THRESHOLD_EXCEEDED' ELSE 'COMPLETED' END,
        'table', :P_TABLE_NM,
        'layer', :P_LAYER,
        'total_records', :v_overall_count,
        'failed_records', :v_fail_count,
        'fail_pct', CASE WHEN :v_overall_count > 0 THEN ROUND((:v_fail_count::FLOAT / :v_overall_count) * 100, 2) ELSE 0 END,
        'threshold_exceeded', :v_threshold_exceeded
    );

EXCEPTION
    WHEN OTHER THEN
        v_err_msg := SQLERRM;
        INSERT INTO P360_DQ.AUDIT.DQ_LOG
            (DQ_BATCH_ID, LAYER, DOMAIN, TABLE_NM, FEED_ID, DQ_START_TS, DQ_END_TS, ERROR_MESSAGE, OVERALL_COUNT, FAILED_COUNT, STATUS, UPDATED_TS)
        VALUES (:P_DQ_BATCH_ID, :P_LAYER, NULL, :P_TABLE_NM, NULL, :v_dq_start_ts, CURRENT_TIMESTAMP(), :v_err_msg, 0, 0, 'Fail', CURRENT_TIMESTAMP());
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'table', :P_TABLE_NM, 'error', :v_err_msg);
END;
$$;
