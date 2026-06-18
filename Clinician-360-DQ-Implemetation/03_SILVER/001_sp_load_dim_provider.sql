-- Loads unified provider dimension from Bronze PASS/PASS-SOFT records into Silver
-- Co-authored with CoCo
/*=============================================================================
  03_SILVER/001_sp_load_dim_provider.sql
=============================================================================*/

USE DATABASE P360_DQ;
USE SCHEMA SILVER;

CREATE OR REPLACE PROCEDURE SILVER.SP_LOAD_DIM_PROVIDER(
    P_RUN_ID VARCHAR, P_MODE VARCHAR DEFAULT 'INCREMENTAL'
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
    CALL P360_DQ.CONFIG.SP_LOG_STEP_START(:v_step_run_id, :P_RUN_ID, 20, 'LOAD_DIM_PROVIDER', 'SILVER', 1);

    IF (:P_MODE = 'FULL') THEN
        TRUNCATE TABLE P360_DQ.SILVER.DIM_PROVIDER;
    END IF;

    MERGE INTO P360_DQ.SILVER.DIM_PROVIDER tgt
    USING (
        SELECT
            n.NPI_NUMBER AS PROVIDER_BK,
            n.PROVIDER_NAME,
            n.PROVIDER_FIRST_NAME,
            n.PROVIDER_LAST_NAME,
            n.CREDENTIAL,
            n.GENDER,
            s.SPECIALTY_NAME AS PRIMARY_SPECIALTY,
            s.SPECIALTY_CATEGORY,
            n.STATE,
            n.ZIP_CODE,
            n.PHONE,
            NULL AS ADDRESS_LINE_1,
            NULL AS CITY,
            NULL AS PROVIDER_TIN,
            n.NPI_NUMBER AS PROVIDER_NPI,
            n.NPI_DEACTIVATION_FLAG AS DELETION_FLAG,
            n.SOURCE_SYSTEM,
            :P_RUN_ID AS _RUN_ID
        FROM P360_DQ.BRONZE.STG_NPI_REGISTRY n
        LEFT JOIN P360_DQ.BRONZE.STG_SPECIALTY_TYPE s
            ON n.TAXONOMY_CODE = s.SPECIALTY_CODE
            AND s.DQ_STATUS IN ('PASS', 'PASS-SOFT')
        WHERE n.DQ_STATUS IN ('PASS', 'PASS-SOFT')
    ) src
    ON tgt.PROVIDER_BK = src.PROVIDER_BK
    WHEN MATCHED THEN UPDATE SET
        PROVIDER_NAME = src.PROVIDER_NAME,
        PROVIDER_FIRST_NAME = src.PROVIDER_FIRST_NAME,
        PROVIDER_LAST_NAME = src.PROVIDER_LAST_NAME,
        CREDENTIAL = src.CREDENTIAL,
        GENDER = src.GENDER,
        PRIMARY_SPECIALTY = src.PRIMARY_SPECIALTY,
        SPECIALTY_CATEGORY = src.SPECIALTY_CATEGORY,
        STATE = src.STATE,
        ZIP_CODE = src.ZIP_CODE,
        PHONE = src.PHONE,
        DELETION_FLAG = src.DELETION_FLAG,
        UPDATE_DT = CURRENT_TIMESTAMP(),
        DQ_STATUS = NULL,
        _RUN_ID = src._RUN_ID
    WHEN NOT MATCHED THEN INSERT (
        PROVIDER_BK, PROVIDER_NAME, PROVIDER_FIRST_NAME, PROVIDER_LAST_NAME,
        CREDENTIAL, GENDER, PRIMARY_SPECIALTY, SPECIALTY_CATEGORY,
        STATE, ZIP_CODE, PHONE, ADDRESS_LINE_1, CITY, PROVIDER_TIN,
        PROVIDER_NPI, DELETION_FLAG, SOURCE_SYSTEM, DQ_STATUS, _RUN_ID
    ) VALUES (
        src.PROVIDER_BK, src.PROVIDER_NAME, src.PROVIDER_FIRST_NAME, src.PROVIDER_LAST_NAME,
        src.CREDENTIAL, src.GENDER, src.PRIMARY_SPECIALTY, src.SPECIALTY_CATEGORY,
        src.STATE, src.ZIP_CODE, src.PHONE, src.ADDRESS_LINE_1, src.CITY, src.PROVIDER_TIN,
        src.PROVIDER_NPI, src.DELETION_FLAG, src.SOURCE_SYSTEM, NULL, src._RUN_ID
    );

    v_insert_count := SQLROWCOUNT;
    CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'COMPLETED', :v_insert_count, :v_insert_count, 0, 0, NULL, NULL, NULL);
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETED', 'rows_written', :v_insert_count);
EXCEPTION
    WHEN OTHER THEN
        LET v_err_msg := SQLERRM;
        CALL P360_DQ.CONFIG.SP_LOG_ERROR(:P_RUN_ID, :v_step_run_id, 'LOAD_DIM_PROVIDER', '', '', :v_err_msg, NULL, 'ERROR');
        CALL P360_DQ.CONFIG.SP_LOG_STEP_END(:v_step_run_id, 'FAILED', 0, 0, 0, 0, :v_err_msg, '', NULL);
        RETURN OBJECT_CONSTRUCT('status', 'FAILED', 'error', :v_err_msg);
END;
$$;
