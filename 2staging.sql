-- ============================================================
-- CRICKET ANALYTICS PROJECT
-- STAGING TRANSFORMATION TASKS
-- ============================================================
--
-- FLOW:
--
-- RAW.STREAM_RAW_DATA
--        ↓
-- DW.TASK_RAW_DATA
--        ↓
-- STAGING.STG_RAW_DATA
--        ↓
-- ┌───────────────┬────────────────┬─────────────────┐
-- ↓               ↓                ↓                 ↓
-- TEAMS         PLAYERS        MATCH_INFO      MATCH_INNINGS
--
-- ============================================================


-- ============================================================
-- 1. ROOT TASK
--    Reads newly arrived records from RAW stream
-- ============================================================

CREATE OR REPLACE TASK CRICKET_ANALYTICS.DW.TASK_RAW_DATA
    WAREHOUSE = CRICKET_WH
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA(
        'CRICKET_ANALYTICS.RAW.STREAM_RAW_DATA'
    )
AS
BEGIN

    TRUNCATE TABLE CRICKET_ANALYTICS.STAGING.STG_RAW_DATA;

    INSERT INTO CRICKET_ANALYTICS.STAGING.STG_RAW_DATA
    SELECT
        RAW_FILE,
        FILENAME
    FROM CRICKET_ANALYTICS.RAW.STREAM_RAW_DATA;

END;


-- ============================================================
-- 2. STAGING TEAMS
-- ============================================================

CREATE OR REPLACE TASK CRICKET_ANALYTICS.DW.TASK_STG_TEAMS
    WAREHOUSE = CRICKET_WH
    AFTER CRICKET_ANALYTICS.DW.TASK_RAW_DATA
AS
BEGIN

    TRUNCATE TABLE CRICKET_ANALYTICS.STAGING.STG_TEAMS;

    INSERT INTO CRICKET_ANALYTICS.STAGING.STG_TEAMS

    SELECT
        F0.VALUE::VARCHAR AS TEAM_NAME,
        RAW_FILE:info.team_type::VARCHAR AS TEAM_TYPE

    FROM CRICKET_ANALYTICS.STAGING.STG_RAW_DATA,

    LATERAL FLATTEN(
        RAW_FILE:info.teams
    ) F0

    GROUP BY ALL;

END;


-- ============================================================
-- 3. STAGING PLAYERS
-- ============================================================

CREATE OR REPLACE TASK CRICKET_ANALYTICS.DW.TASK_STG_PLAYERS
    WAREHOUSE = CRICKET_WH
    AFTER CRICKET_ANALYTICS.DW.TASK_RAW_DATA
AS
BEGIN

    TRUNCATE TABLE CRICKET_ANALYTICS.STAGING.STG_PLAYERS;

    INSERT INTO CRICKET_ANALYTICS.STAGING.STG_PLAYERS

    SELECT
        F1.VALUE::STRING AS PLAYER_NAME,
        F0.KEY::STRING AS TEAM_NAME

    FROM CRICKET_ANALYTICS.STAGING.STG_RAW_DATA,

    LATERAL FLATTEN(
        RAW_FILE:info.players
    ) F0,

    LATERAL FLATTEN(
        F0.VALUE
    ) F1

    GROUP BY ALL;

END;


-- ============================================================
-- 4. STAGING MATCH INFORMATION
-- ============================================================

CREATE OR REPLACE TASK CRICKET_ANALYTICS.DW.TASK_STG_MATCH
    WAREHOUSE = CRICKET_WH
    AFTER CRICKET_ANALYTICS.DW.TASK_RAW_DATA
AS
BEGIN

    TRUNCATE TABLE CRICKET_ANALYTICS.STAGING.STG_MATCH_INFO;

    INSERT INTO CRICKET_ANALYTICS.STAGING.STG_MATCH_INFO

    SELECT

        RAW_FILE:info.match_type::STRING
            AS MATCH_TYPE,

        RAW_FILE:info.gender::STRING
            AS GENDER,

        RAW_FILE:info.season::STRING
            AS SEASON,

        RAW_FILE:info.city::STRING
            AS CITY,

        RAW_FILE:info.venue::STRING
            AS VENUE,

        RAW_FILE:info.dates[0]::DATE
            AS MATCH_DATE,

        RAW_FILE:info.teams[0]::STRING
            AS TEAM1,

        RAW_FILE:info.teams[1]::STRING
            AS TEAM2,

        RAW_FILE:info.toss.winner::STRING
            AS TOSS_WINNER,

        RAW_FILE:info.toss.decision::STRING
            AS TOSS_DECISION,

        RAW_FILE:info.outcome.winner::STRING
            AS MATCH_WINNER,

        CASE

            WHEN RAW_FILE:info.outcome.by.wickets::STRING
                 IS NOT NULL

            THEN RAW_FILE:info.outcome.by.wickets::STRING
                 || ' wickets'

            WHEN RAW_FILE:info.outcome.by.runs::STRING
                 IS NOT NULL

            THEN RAW_FILE:info.outcome.by.runs::STRING
                 || ' runs'

            ELSE 'no result'

        END AS MARGIN,

        RAW_FILE:info.event.name::STRING
            AS EVENT_NAME,

        RAW_FILE:info.team_type::STRING
            AS EVENT_TYPE,

        RAW_FILE:info.player_of_match[0]::STRING
            AS POM,

        FILENAME

    FROM CRICKET_ANALYTICS.STAGING.STG_RAW_DATA;

END;


-- ============================================================
-- 5. STAGING MATCH INNINGS
-- ============================================================

CREATE OR REPLACE TASK CRICKET_ANALYTICS.DW.TASK_STG_MATCH_INNINGS
    WAREHOUSE = CRICKET_WH
    AFTER CRICKET_ANALYTICS.DW.TASK_RAW_DATA
AS
BEGIN

    TRUNCATE TABLE CRICKET_ANALYTICS.STAGING.STG_MATCH_INNINGS;

    INSERT INTO CRICKET_ANALYTICS.STAGING.STG_MATCH_INNINGS

    SELECT

        F0.INDEX + 1
            AS INNING_ID,

        F.VALUE:over::INT + 1
            AS OVER,

        F0.VALUE:team::STRING
            AS BATTING_TEAM,

        F1.INDEX + 1
            AS BALL_IN_OVER,

        F1.VALUE:batter::STRING
            AS BATTER,

        F1.VALUE:bowler::STRING
            AS BOWLER,

        F1.VALUE:non_striker::STRING
            AS NON_STRIKER,

        F1.VALUE:runs.batter::INT
            AS RUNS_BATTER,

        OBJECT_KEYS(
            F1.VALUE:extras
        )[0]::STRING
            AS EXTRA_TYPE,

        F1.VALUE:runs.extras::INT
            AS RUNS_EXTRAS,

        F1.VALUE:runs.total::INT
            AS RUNS_TOTAL,

        F1.VALUE:wickets[0].kind::STRING
            AS DISMISSAL_KIND,

        F1.VALUE:wickets[0].player_out::STRING
            AS OUT_PLAYER,

        COALESCE(
            CEIL(F0.VALUE:powerplays[0].from),
            START_OVER
        )
            AS POWERPLAYS_START_OVER,

        COALESCE(
            CEIL(F0.VALUE:powerplays[0].to),
            END_OVER
        )
            AS POWERPLAYS_END_OVER,

        CASE

            WHEN OVER BETWEEN
                 POWERPLAYS_START_OVER
                 AND POWERPLAYS_END_OVER

            THEN 1

            ELSE 0

        END AS IS_POWERPLAY,

        FILENAME

    FROM CRICKET_ANALYTICS.STAGING.STG_RAW_DATA

    LEFT JOIN CRICKET_ANALYTICS.RAW.DEFAULT_POWERPLAYS

        ON RAW_FILE:info.match_type::STRING
           =
           DEFAULT_POWERPLAYS.MATCH_TYPE

    ,

    LATERAL FLATTEN(
        RAW_FILE:innings
    ) F0

    ,

    LATERAL FLATTEN(
        F0.VALUE:overs
    ) F

    ,

    LATERAL FLATTEN(
        F.VALUE:deliveries
    ) F1;

END;


-- ============================================================
-- 6. RESUME CHILD TASKS
-- ============================================================

ALTER TASK CRICKET_ANALYTICS.DW.TASK_STG_MATCH_INNINGS
RESUME;

ALTER TASK CRICKET_ANALYTICS.DW.TASK_STG_MATCH
RESUME;

ALTER TASK CRICKET_ANALYTICS.DW.TASK_STG_TEAMS
RESUME;

ALTER TASK CRICKET_ANALYTICS.DW.TASK_STG_PLAYERS
RESUME;


-- ============================================================
-- 7. RESUME ROOT TASK LAST
-- ============================================================

ALTER TASK CRICKET_ANALYTICS.DW.TASK_RAW_DATA
RESUME;


-- ============================================================
-- 8. VALIDATION QUERIES
-- ============================================================

SELECT *
FROM CRICKET_ANALYTICS.STAGING.STG_TEAMS;


SELECT *
FROM CRICKET_ANALYTICS.STAGING.STG_PLAYERS;


SELECT *
FROM CRICKET_ANALYTICS.STAGING.STG_MATCH_INFO;


SELECT *
FROM CRICKET_ANALYTICS.STAGING.STG_MATCH_INNINGS;