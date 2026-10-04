-- ============================================================
-- CRICKET ANALYTICS PROJECT
-- S3 → SNOWFLAKE RAW INGESTION
-- ============================================================


-- ============================================================
-- 1. CREATE STORAGE INTEGRATION
--    Connects Snowflake to AWS S3 using IAM ROLE
-- ============================================================

CREATE OR REPLACE STORAGE INTEGRATION S3_CA_INT
TYPE = EXTERNAL_STAGE
STORAGE_PROVIDER = S3
ENABLED = TRUE
STORAGE_AWS_ROLE_ARN =
    'arn:aws:iam::301356687040:role/SnowflakeCricketS3Role'
STORAGE_ALLOWED_LOCATIONS =
    ('s3://snowflake-cricket-analytics/');


-- ============================================================
-- 2. CHECK STORAGE INTEGRATION DETAILS
-- ============================================================

DESC INTEGRATION S3_CA_INT;


-- ============================================================
-- 3. CREATE EXTERNAL STAGE
--    Points Snowflake to our S3 bucket
-- ============================================================

CREATE OR REPLACE STAGE CRICKET_ANALYTICS.RAW.S3_EXT_STAGE
    STORAGE_INTEGRATION = S3_CA_INT
    FILE_FORMAT = (
        TYPE = JSON
    )
    URL = 's3://snowflake-cricket-analytics/';


-- ============================================================
-- 4. LIST FILES AVAILABLE IN S3
-- ============================================================

LIST @CRICKET_ANALYTICS.RAW.S3_EXT_STAGE;


-- ============================================================
-- 5. CREATE SNOWPIPE
--    S3 → RAW_DATA
--
--    AUTO_INGEST = TRUE
--    This is the architecture used in the original project.
-- ============================================================

CREATE OR REPLACE PIPE CRICKET_ANALYTICS.RAW.S3_CA_PIPE
AUTO_INGEST = TRUE
AS
COPY INTO CRICKET_ANALYTICS.RAW.RAW_DATA
FROM
(
    SELECT
        $1,
        METADATA$FILENAME
    FROM @CRICKET_ANALYTICS.RAW.S3_EXT_STAGE
)
PATTERN = '.*[.]json'
ON_ERROR = CONTINUE;


-- ============================================================
-- 6. CHECK PIPE CONFIGURATION
-- ============================================================

DESC PIPE CRICKET_ANALYTICS.RAW.S3_CA_PIPE;


-- ============================================================
-- 7. CHECK PIPE STATUS
-- ============================================================

SELECT SYSTEM$PIPE_STATUS(
    'CRICKET_ANALYTICS.RAW.S3_CA_PIPE'
);


-- ============================================================
-- 8. REFRESH PIPE
--    Attempts to load files already present in S3
-- ============================================================

ALTER PIPE CRICKET_ANALYTICS.RAW.S3_CA_PIPE
REFRESH;


-- ============================================================
-- 9. CHECK RAW DATA
-- ============================================================

SELECT *
FROM CRICKET_ANALYTICS.RAW.RAW_DATA;


-- ============================================================
-- 10. COUNT RAW RECORDS
-- ============================================================

SELECT
    COUNT(*) AS RAW_RECORD_COUNT
FROM CRICKET_ANALYTICS.RAW.RAW_DATA;


-- ============================================================
-- 11. CHECK LOADED FILES
-- ============================================================

SELECT
    FILENAME,
    COUNT(*) AS RECORD_COUNT
FROM CRICKET_ANALYTICS.RAW.RAW_DATA
GROUP BY FILENAME
ORDER BY FILENAME;


-- ============================================================
-- 12. INSPECT MATCH INFORMATION
-- ============================================================

SELECT
    RAW_FILE:info AS MATCH_INFO,
    FILENAME
FROM CRICKET_ANALYTICS.RAW.RAW_DATA;


-- ============================================================
-- 13. CREATE STREAM
--    Captures new records arriving in RAW_DATA
-- ============================================================

CREATE OR REPLACE STREAM CRICKET_ANALYTICS.RAW.STREAM_RAW_DATA
ON TABLE CRICKET_ANALYTICS.RAW.RAW_DATA
APPEND_ONLY = TRUE;


-- ============================================================
-- 14. CHECK STREAM
-- ============================================================

SELECT *
FROM CRICKET_ANALYTICS.RAW.STREAM_RAW_DATA;