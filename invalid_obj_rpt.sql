-- invalid_objects_report.sql
-- Author:  Kellyn Gorman, Advocate, Redgate
-- Purpose: Report invalid objects per schema
-- Output : <database_name>_inv_rpt.out
-- Run with SQL*Plus or SQLcl: user/pw@db @invalid_objects_report.sql

-- =========================
-- Report Setup
-- =========================
SET TERMOUT ON
SET ECHO OFF
SET FEEDBACK OFF
SET HEADING ON
SET VERIFY OFF
SET PAGESIZE 50000
SET LINESIZE 200
SET TRIMSPOOL ON
SET TAB OFF
SET WRAP OFF

COLUMN db_name NEW_VALUE DB_NAME NOPRINT
SELECT LOWER(name) AS db_name FROM v$database;

COLUMN run_ts NEW_VALUE RUN_TS NOPRINT
SELECT TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS') AS run_ts FROM dual;

DEF OUTFILE = &&DB_NAME._&&RUN_TS._inv_rpt.out

-- =========================
-- Column formatting
-- =========================
COLUMN owner         FORMAT A25  HEADING 'Schema'
COLUMN object_type   FORMAT A20  HEADING 'Object Type'
COLUMN object_name   FORMAT A45  HEADING 'Object Name'
COLUMN status        FORMAT A8   HEADING 'Status'
COLUMN last_ddl_time FORMAT A19  HEADING 'Last DDL Time'

BREAK ON owner SKIP 1

SPOOL &&OUTFILE

PROMPT ============================================================
PROMPT Invalid Objects Report
PROMPT Database : &&DB_NAME
PROMPT Generated: &&_DATE
PROMPT Output   : &&OUTFILE
PROMPT ============================================================
PROMPT

-- =========================
-- Exclusion list
-- =========================
WITH excluded_schemas AS (
    SELECT 'SYS' owner FROM dual UNION ALL
    SELECT 'SYSTEM' FROM dual UNION ALL
    SELECT 'HR' FROM dual UNION ALL
    SELECT 'OE' FROM dual UNION ALL
    SELECT 'PM' FROM dual UNION ALL
    SELECT 'SH' FROM dual UNION ALL
    SELECT 'SCOTT' FROM dual UNION ALL
    SELECT 'APEX_PUBLIC_USER' FROM dual UNION ALL
    SELECT 'FLOWS_FILES' FROM dual UNION ALL
    SELECT 'ANONYMOUS' FROM dual
),
base AS (
    SELECT
        o.owner,
        o.object_type,
        o.object_name,
        o.status,
        TO_CHAR(o.last_ddl_time, 'YYYY-MM-DD HH24:MI:SS') AS last_ddl_time
    FROM dba_objects o
    WHERE o.status = 'INVALID'
      AND o.owner NOT IN (SELECT owner FROM excluded_schemas)
      -- Exclude Oracle-maintained schemas (19c+)
      AND o.owner NOT IN (
          SELECT u.username
          FROM dba_users u
          WHERE u.oracle_maintained = 'Y'
      )
)
SELECT
    owner,
    object_type,
    object_name,
    status,
    last_ddl_time
FROM base
ORDER BY owner, object_type, object_name;

PROMPT
PROMPT ============================================================
PROMPT Summary (invalid object counts by schema)
PROMPT ============================================================
PROMPT

COLUMN invalid_count FORMAT 999,999 HEADING 'Invalid Count'
SELECT
    owner,
    COUNT(*) AS invalid_count
FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN (
      SELECT u.username
      FROM dba_users u
      WHERE u.oracle_maintained = 'Y'
  )
GROUP BY owner
ORDER BY invalid_count DESC, owner;

PROMPT
PROMPT ============================================================
PROMPT End of Report
PROMPT ============================================================

SPOOL OFF
CLEAR BREAKS
SET FEEDBACK ON
