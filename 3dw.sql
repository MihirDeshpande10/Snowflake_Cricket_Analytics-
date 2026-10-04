-- ============================================================
-- CRICKET ANALYTICS PROJECT
-- DATA WAREHOUSE TRANSFORMATION
-- ============================================================
--
-- FLOW:
--
-- STAGING TABLES
--      ↓
-- STG_TEAMS
-- STG_PLAYERS
-- STG_MATCH_INFO
-- STG_MATCH_INNINGS
--      ↓
-- DW TABLES
--      ↓
-- TEAMS
-- PLAYERS
-- MATCH_INFO
-- MATCH_INNINGS
--
-- ============================================================


-- ============================================================
-- 1. LOAD TEAMS
-- ============================================================

CREATE OR REPLACE TASK CRICKET_ANALYTICS.DW.TASK_TEAMS
    WAREHOUSE = CRICKET_WH
    AFTER
        CRICKET_ANALYTICS.DW.TASK_STG_TEAMS,
        CRICKET_ANALYTICS.DW.TASK_STG_PLAYERS,
        CRICKET_ANALYTICS.DW.TASK_STG_MATCH,
        CRICKET_ANALYTICS.DW.TASK_STG_MATCH_INNINGS
AS

INSERT INTO CRICKET_ANALYTICS.DW.TEAMS
SELECT
    CRICKET_ANALYTICS.RAW.SEQ_TEAMS.NEXTVAL AS TEAM_ID,
    TEAM_NAME,
    TEAM_TYPE
FROM CRICKET_ANALYTICS.STAGING.STG_TEAMS
WHERE TEAM_NAME NOT IN
(
    SELECT TEAM_NAME
    FROM CRICKET_ANALYTICS.DW.TEAMS
);


-- ============================================================
-- 2. LOAD / UPDATE PLAYERS
--
-- A player can belong to multiple teams.
-- Therefore the TEAMS column is maintained as an ARRAY.
-- ============================================================

CREATE OR REPLACE TASK CRICKET_ANALYTICS.DW.TASK_PLAYERS
    WAREHOUSE = CRICKET_WH
    AFTER CRICKET_ANALYTICS.DW.TASK_TEAMS
AS

MERGE INTO CRICKET_ANALYTICS.DW.PLAYERS AS TARGET

USING
(
    SELECT
        P.PLAYER_NAME,
        ARRAY_AGG(DISTINCT T.TEAM_ID) AS TEAMS

    FROM CRICKET_ANALYTICS.STAGING.STG_PLAYERS P

    INNER JOIN CRICKET_ANALYTICS.DW.TEAMS T
        ON P.TEAM_NAME = T.TEAM_NAME

    GROUP BY P.PLAYER_NAME

) AS SOURCE

ON TARGET.PLAYER_NAME = SOURCE.PLAYER_NAME


WHEN MATCHED THEN

    UPDATE SET
        TEAMS =
            ARRAY_DISTINCT(
                ARRAY_CAT(
                    TARGET.TEAMS,
                    SOURCE.TEAMS
                )
            )


WHEN NOT MATCHED THEN

    INSERT
    (
        PLAYER_ID,
        PLAYER_NAME,
        TEAMS
    )

    VALUES
    (
        CRICKET_ANALYTICS.RAW.SEQ_PLAYERS.NEXTVAL,
        SOURCE.PLAYER_NAME,
        SOURCE.TEAMS
    );


-- ============================================================
-- 3. LOAD MATCH INFORMATION
-- ============================================================

CREATE OR REPLACE TASK CRICKET_ANALYTICS.DW.TASK_MATCH_INFO
    WAREHOUSE = CRICKET_WH
    AFTER CRICKET_ANALYTICS.DW.TASK_PLAYERS
AS

INSERT INTO CRICKET_ANALYTICS.DW.MATCH_INFO

SELECT

    CRICKET_ANALYTICS.RAW.SEQ_MATCHES.NEXTVAL
        AS MATCH_ID,

    MI.MATCH_TYPE,

    MI.GENDER,

    MI.SEASON,

    MI.CITY,

    MI.VENUE,

    MI.MATCH_DATE,

    T1.TEAM_ID
        AS TEAM1_ID,

    T2.TEAM_ID
        AS TEAM2_ID,

    T3.TEAM_ID
        AS TOSS_WINNER_ID,

    MI.TOSS_DECISION,

    T4.TEAM_ID
        AS MATCH_WINNER_ID,

    MI.MARGIN,

    MI.EVENT_NAME,

    MI.EVENT_TYPE,

    P.PLAYER_ID
        AS POM_ID,

    MI.FILENAME

FROM CRICKET_ANALYTICS.STAGING.STG_MATCH_INFO MI

INNER JOIN CRICKET_ANALYTICS.DW.TEAMS T1
    ON MI.TEAM1 = T1.TEAM_NAME

INNER JOIN CRICKET_ANALYTICS.DW.TEAMS T2
    ON MI.TEAM2 = T2.TEAM_NAME

INNER JOIN CRICKET_ANALYTICS.DW.TEAMS T3
    ON MI.TOSS_WINNER = T3.TEAM_NAME

LEFT JOIN CRICKET_ANALYTICS.DW.TEAMS T4
    ON MI.MATCH_WINNER = T4.TEAM_NAME

LEFT JOIN CRICKET_ANALYTICS.DW.PLAYERS P
    ON MI.POM = P.PLAYER_NAME

WHERE MI.FILENAME NOT IN
(
    SELECT FILENAME
    FROM CRICKET_ANALYTICS.DW.MATCH_INFO
);


-- ============================================================
-- 4. LOAD MATCH INNINGS / BALL-BY-BALL DATA
-- ============================================================

CREATE OR REPLACE TASK CRICKET_ANALYTICS.DW.TASK_MATCH_INNINGS
    WAREHOUSE = CRICKET_WH
    AFTER CRICKET_ANALYTICS.DW.TASK_MATCH_INFO
AS

INSERT INTO CRICKET_ANALYTICS.DW.MATCH_INNINGS

SELECT

    MI.MATCH_ID,

    ING.INNING_ID,

    ING.OVER,

    T1.TEAM_ID
        AS BATTING_TEAM,

    ING.BALL_IN_OVER,

    ING.BATTER,

    ING.BOWLER,

    ING.NON_STRIKER,

    ING.RUNS_BATTER,

    ING.EXTRA_TYPE,

    ING.RUNS_EXTRAS,

    ING.RUNS_TOTAL,

    ING.DISMISSAL_KIND,

    ING.OUT_PLAYER,

    ING.IS_POWERPLAY

FROM CRICKET_ANALYTICS.STAGING.STG_MATCH_INNINGS ING

INNER JOIN CRICKET_ANALYTICS.DW.MATCH_INFO MI

    ON ING.FILENAME = MI.FILENAME

INNER JOIN CRICKET_ANALYTICS.DW.TEAMS T1

    ON ING.BATTING_TEAM = T1.TEAM_NAME

WHERE MI.MATCH_ID NOT IN
(
    SELECT MATCH_ID
    FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS
);


-- ============================================================
-- 5. RESUME DW TASKS
--
-- Child tasks first.
-- ============================================================

ALTER TASK CRICKET_ANALYTICS.DW.TASK_MATCH_INNINGS
RESUME;

ALTER TASK CRICKET_ANALYTICS.DW.TASK_MATCH_INFO
RESUME;

ALTER TASK CRICKET_ANALYTICS.DW.TASK_TEAMS
RESUME;

ALTER TASK CRICKET_ANALYTICS.DW.TASK_PLAYERS
RESUME;


-- ============================================================
-- 6. VALIDATION — TEAMS
-- ============================================================

SELECT *
FROM CRICKET_ANALYTICS.DW.TEAMS;


-- ============================================================
-- 7. VALIDATION — PLAYERS
-- ============================================================

SELECT *
FROM CRICKET_ANALYTICS.DW.PLAYERS;


-- ============================================================
-- 8. VALIDATION — MATCH INFO
-- ============================================================

SELECT *
FROM CRICKET_ANALYTICS.DW.MATCH_INFO;


-- ============================================================
-- 9. VALIDATION — MATCH INNINGS
-- ============================================================

SELECT *
FROM CRICKET_ANALYTICS.DW.MATCH_INNINGS;


-- ============================================================
-- 10. PLAYER → TEAM ARRAY DEMO
-- ============================================================

SELECT
    P.PLAYER_ID,
    P.PLAYER_NAME,
    T.VALUE AS TEAM_ID

FROM CRICKET_ANALYTICS.DW.PLAYERS P,

LATERAL FLATTEN(
    INPUT => P.TEAMS
) T;


-- ============================================================
-- 11. PLAYER TABLE CHECK
-- ============================================================

SELECT *
FROM CRICKET_ANALYTICS.DW.PLAYERS;