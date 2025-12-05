/*------------------------------------------------------------------
  schema_inv_report.sql
  Author  : Kellyn Gorman, Redgate
  Purpose  : Generate an inventory report for a
             single schema (user) in an Oracle database.
  Usage    : sqlplus / as sysdba @schema_inv_report.sql
  Output   : db_schema_inventory_<dbname>_<schema>.txt in current dir
-------------------------------------------------------------------*/

-- Basic report formatting
SET ECHO        OFF
SET FEEDBACK    ON
SET HEADING     ON
SET LINESIZE    200
SET PAGESIZE    5000
SET VERIFY      OFF
SET TRIMSPOOL   ON
SET TAB         OFF
SET TERMOUT     OFF

-- Get database name for spool file
COLUMN db_name NEW_VALUE DB_NAME NOPRINT
SELECT LOWER(name) db_name FROM v$database;

SET TERMOUT ON
PROMPT

PROMPT ############################################################
PROMPT #         ORACLE DATABASE / SCHEMA INVENTORY REPORT        #
PROMPT #     Database: &&DB_NAME                                  #
PROMPT #     Generated on: &_DATE                                 #
PROMPT ############################################################
PROMPT

-- Prompt for schema name (user)
ACCEPT p_schema CHAR PROMPT 'Enter schema name (user) to report on: '

-- Normalize to uppercase for catalog views
SET TERMOUT OFF
COLUMN schema_name_upper NEW_VALUE SCHEMA_NAME_UPPER NOPRINT
SELECT UPPER('&p_schema') AS schema_name_upper FROM dual;
SET TERMOUT ON

PROMPT
PROMPT Running report for schema: &&SCHEMA_NAME_UPPER
PROMPT

-- Spool to a text file in the current directory
SPOOL db_schema_inventory_&&DB_NAME._&&SCHEMA_NAME_UPPER..txt

TTITLE OFF
BTITLE OFF

/******************************************************************
 * SECTION 1: Database Overview
 * "Basic information about this Oracle database"
 ******************************************************************/

PROMPT ============================================================
PROMPT Section 1 - Database Overview
PROMPT (Basic information: database name, version, platform, and role)
PROMPT ============================================================

COLUMN db_name         FORMAT A15       HEADING 'DB Name'
COLUMN db_unique_name  FORMAT A25       HEADING 'DB Unique Name'
COLUMN database_role   FORMAT A20       HEADING 'Database Role'
COLUMN open_mode       FORMAT A15       HEADING 'Open Mode'
COLUMN log_mode        FORMAT A12       HEADING 'Log Mode'
COLUMN protection_mode FORMAT A25       HEADING 'Protection Mode'
COLUMN oracle_version  FORMAT A15       HEADING 'Oracle Version'
COLUMN host_name       FORMAT A30       HEADING 'Host Name'
COLUMN platform_os     FORMAT A30       HEADING 'Platform / OS'
COLUMN instance_type   FORMAT A30       HEADING 'Instance Type'

SELECT
    d.name            AS db_name,
    d.db_unique_name,
    d.database_role,
    d.open_mode,
    d.log_mode,
    d.protection_mode,
    i.version         AS oracle_version,
    i.host_name,
    d.platform_name   AS platform_os,
    (SELECT CASE
              WHEN COUNT(*) > 1 THEN 'RAC (Real Application Clusters)'
              ELSE 'Single Instance'
            END
       FROM gv$instance) AS instance_type
FROM   v$database d
CROSS  JOIN v$instance i;

PROMPT ===============================================================
PROMPT Section 1b: Multitenancy Architecture
PROMPT Multitenant (PDB) Information and Size
PROMPT ===============================================================

COLUMN name            FORMAT A25       HEADING 'Container Name'
COLUMN backup_status   FORMAT A15       HEADING 'Backup Status'
COLUMN total_size      FORMAT A15       HEADING 'Total Size in MB'

select con_id AS "Container ID", 
name, 
pdb_count AS "PDBs Owned", 
local_undo AS "Local Undo", 
backup_status, 
total_size/1024/1024 
from v$containers;

PROMPT

/******************************************************************
 * SECTION 2: Schema Summary and Object Count
 * "What kind of schema is this and how many objects
 *               does it own?"
 * Notes:
 *   - Schema Type:
 *       PERMANENT : Normal, active schema
 *       LOCKED    : Accounts currently locked
 ******************************************************************/

PROMPT ==============================================================
PROMPT Section 2 - Schema Summary
PROMPT (Account details and object count for &&SCHEMA_NAME_UPPER)
PROMPT ==============================================================

COLUMN schema_name   FORMAT A25        HEADING 'Schema Name'
COLUMN schema_type   FORMAT A15        HEADING 'Schema Type'
COLUMN object_count  FORMAT 999,999,999 HEADING 'Object Count'
COLUMN account_status FORMAT A25       HEADING 'Account Status'
COLUMN default_ts     FORMAT A30       HEADING 'Default Tablespace'
COLUMN temp_ts        FORMAT A30       HEADING 'Temporary Tablespace'
COLUMN created        FORMAT A25       HEADING 'Created'

SELECT
    u.username AS schema_name,
    CASE
      WHEN u.account_status LIKE 'LOCKED%' THEN 'LOCKED'
      ELSE 'PERMANENT'
    END                        AS schema_type,
    u.account_status,
    u.default_tablespace       AS default_ts,
    u.temporary_tablespace     AS temp_ts,
    TO_CHAR(u.created,'YYYY-MM-DD HH24:MI:SS') AS created,
    (SELECT COUNT(*)
       FROM dba_objects o
      WHERE o.owner = u.username) AS object_count
FROM   dba_users u
WHERE  u.username = '&&SCHEMA_NAME_UPPER';

PROMPT

/******************************************************************
 * SECTION 3: Tablespace Information for Schema
 * "What Tablespaces does the user have available and how much space?"
 ******************************************************************/

PROMPT ==============================================================
PROMPT Section 3 - Tablespace Names and Space
PROMPT Report on tablespace used by the schema
PROMPT ==============================================================

SET TERMOUT ON
SET ECHO OFF
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 160
SET TRIMSPOOL ON

VARIABLE v_username VARCHAR2(30);

BEGIN
    :v_username := '&&SCHEMA_NAME_UPPER';
END;
/

COLUMN rep_user NEW_VALUE rep_user
SELECT :v_username AS rep_user FROM dual;

TTITLE CENTER 'Tablespace Quota and Usage for &rep_user' SKIP 1

COLUMN username        FORMAT A20               HEADING 'User'
COLUMN tablespace_name FORMAT A30               HEADING 'Tablespace'
COLUMN quota_type      FORMAT A10               HEADING 'Quota Type'
COLUMN quota_mb        FORMAT 999,999,999.99    HEADING 'Quota MB'
COLUMN used_mb         FORMAT 999,999,999.99    HEADING 'Used MB'
COLUMN pct_used        FORMAT 999.99            HEADING '% Used'

BREAK ON username SKIP 1

WITH seg AS (
    SELECT owner                 AS username,
           tablespace_name,
           SUM(bytes) / (1024*1024) AS used_mb
    FROM   dba_segments
    WHERE  owner = :v_username
    GROUP  BY owner, tablespace_name
),
quota AS (
    SELECT username,
           tablespace_name,
           max_bytes,
           bytes
    FROM   dba_ts_quotas
    WHERE  username = :v_username
)
SELECT COALESCE(q.username, s.username)          AS username,
       COALESCE(q.tablespace_name, s.tablespace_name) AS tablespace_name,
       CASE 
           WHEN q.max_bytes = -1 THEN 'UNLIMITED'
           WHEN q.max_bytes IS NULL THEN 'NONE'
           ELSE 'LIMITED'
       END                                       AS quota_type,
       CASE 
           WHEN q.max_bytes IS NULL OR q.max_bytes = -1 THEN NULL
           ELSE ROUND(q.max_bytes / (1024*1024), 2)
       END                                       AS quota_mb,
       NVL(ROUND(s.used_mb, 2), 0)               AS used_mb,
       CASE 
           WHEN q.max_bytes IS NULL 
                OR q.max_bytes IN (-1, 0) 
                OR s.used_mb IS NULL
           THEN NULL
           ELSE ROUND((s.used_mb * 1024*1024) / q.max_bytes * 100, 2)
       END                                       AS pct_used
FROM   quota q
       FULL OUTER JOIN seg s
         ON q.username       = s.username
        AND q.tablespace_name = s.tablespace_name
ORDER  BY tablespace_name;

TTITLE OFF
CLEAR COLUMNS
CLEAR BREAKS

/******************************************************************
 * SECTION 4: Schema Privileges Information
 * "What Privileges and roles does the schema have?"
 ******************************************************************/

PROMPT ============================================================
PROMPT Section 4 - Schema Privileges and Roles
PROMPT ============================================================

SET TERMOUT ON
SET ECHO OFF
SET VERIFY OFF
SET FEEDBACK ON
SET PAGESIZE 200
SET LINESIZE 200
SET TRIMSPOOL ON

VARIABLE v_username VARCHAR2(30);

BEGIN
    :v_username := '&&SCHEMA_NAME_UPPER';
END;
/

COLUMN rep_user NEW_VALUE rep_user
SELECT :v_username AS rep_user FROM dual;

TTITLE CENTER 'Complete Grants Report for &rep_user' SKIP 1

COLUMN privilege_type FORMAT A8   HEADING 'Type'
COLUMN privilege_name FORMAT A30  HEADING 'Privilege/Role'
COLUMN owner          FORMAT A20  HEADING 'Owner'
COLUMN object_name    FORMAT A30  HEADING 'Object'
COLUMN via            FORMAT A8   HEADING 'Via'
COLUMN via_role       FORMAT A30  HEADING 'Role Source'
COLUMN admin_option   FORMAT A5   HEADING 'ADMIN'
COLUMN grantable      FORMAT A9   HEADING 'GRANTABLE'

BREAK ON REPORT

SELECT privilege_type,
       privilege_name,
       owner,
       object_name,
       via,
       via_role,
       admin_option,
       grantable
FROM (
    SELECT 'ROLE'          AS privilege_type,
           dr.granted_role AS privilege_name,
           NULL            AS owner,
           NULL            AS object_name,
           'DIRECT'        AS via,
           NULL            AS via_role,
           dr.admin_option,
           NULL            AS grantable
    FROM   dba_role_privs dr
    WHERE  dr.grantee = :v_username
    UNION ALL
    SELECT 'SYS_PRIV'      AS privilege_type,
           dsp.privilege   AS privilege_name,
           NULL            AS owner,
           NULL            AS object_name,
           'DIRECT'        AS via,
           NULL            AS via_role,
           dsp.admin_option,
           NULL            AS grantable
    FROM   dba_sys_privs dsp
    WHERE  dsp.grantee = :v_username
    UNION ALL
    SELECT 'OBJ_PRIV'      AS privilege_type,
           dtp.privilege   AS privilege_name,
           dtp.owner       AS owner,
           dtp.table_name  AS object_name,
           'DIRECT'        AS via,
           NULL            AS via_role,
           NULL            AS admin_option,
           dtp.grantable   AS grantable
    FROM   dba_tab_privs dtp
    WHERE  dtp.grantee = :v_username
    UNION ALL
    SELECT 'SYS_PRIV'      AS privilege_type,
           rsp.privilege   AS privilege_name,
           NULL            AS owner,
           NULL            AS object_name,
           'ROLE'          AS via,
           dr.granted_role AS via_role,
           rsp.admin_option,
           NULL            AS grantable
    FROM   dba_role_privs dr
           JOIN role_sys_privs rsp
             ON rsp.role = dr.granted_role
    WHERE  dr.grantee = :v_username
    UNION ALL
    SELECT 'OBJ_PRIV'      AS privilege_type,
           rtp.privilege   AS privilege_name,
           rtp.owner       AS owner,
           rtp.table_name  AS object_name,
           'ROLE'          AS via,
           dr.granted_role AS via_role,
           NULL            AS admin_option,
           rtp.grantable   AS grantable
    FROM   dba_role_privs dr
           JOIN role_tab_privs rtp
             ON rtp.role = dr.granted_role
    WHERE  dr.grantee = :v_username
)
ORDER BY privilege_type,
         privilege_name,
         owner,
         object_name,
         via,
         via_role;

TTITLE OFF
CLEAR COLUMNS
CLEAR BREAKS

/******************************************************************
 * SECTION 6: Partitioning and Subpartitioning in the Schema
 * "How does this schema use table partitioning?"
 * - partitioned_table_count      : Tables that are partitioned
 * - subpartitioned_table_count   : Partitioned tables that also
 *                                  use subpartitions
 ******************************************************************/

PROMPT ============================================================
PROMPT Section 6 - Partitioning Usage in Selected Schema
PROMPT (Partitioned and subpartitioned tables in &&SCHEMA_NAME_UPPER)
PROMPT ============================================================

COLUMN partition_schema          FORMAT A30          HEADING 'Schema Name'
COLUMN partitioned_table_count   FORMAT 999,999,999  HEADING 'Partitioned Tables'
COLUMN subpartitioned_table_cnt  FORMAT 999,999,999  HEADING 'Subpartitioned Tables'

SELECT
    owner AS partition_schema,
    COUNT(*) AS partitioned_table_count,
    SUM(
      CASE
        WHEN subpartitioning_type IS NULL
             OR subpartitioning_type = 'NONE'
        THEN 0
        ELSE 1
      END
    ) AS subpartitioned_table_cnt
FROM   dba_part_tables
WHERE  owner = '&&SCHEMA_NAME_UPPER'
GROUP BY owner;

PROMPT

/******************************************************************
 * SECTION 7: Hidden or Invisible Objects in the Schema
 * “Which objects in this schema are hidden or invisible?"
 * Here we treat as "hidden or invisible":
 *   - Hidden columns in tables (HIDDEN_COLUMN = 'YES')
 *   - Columns with internal SYS_ names
 *   - Invisible indexes (VISIBILITY = 'INVISIBLE')
 ******************************************************************/

PROMPT ============================================================
PROMPT Section 7a - Hidden Objects in Selected Schema
PROMPT (Hidden columns in &&SCHEMA_NAME_UPPER)
PROMPT ============================================================

COLUMN inv_idx_schema           FORMAT A30          HEADING 'Schema Name'
COLUMN hidden_columns           FORMAT A30          HEADING 'Schema Name'
COLUMN inv_col_count            FORMAT 999,999,999  HEADING 'Invisible Object Count'
COLUMN hidden_col_count         FORMAT 999,999,999  HEADING 'Hidden Object Count'

SELECT
    owner AS hidden_columns,
    COUNT(*) AS hidden_col_count
FROM (
    SELECT
        owner,
        table_name,
        column_name AS object_name
    FROM   dba_tab_cols
    WHERE  owner = '&&SCHEMA_NAME_UPPER'
      AND  (hidden_column = 'YES'
            OR column_name LIKE 'SYS\_%' ESCAPE '\')
)
GROUP BY owner
ORDER BY hidden_col_count DESC, hidden_columns;


PROMPT ============================================================
PROMPT Section 7b - Invisible Objects in Selected Schema
PROMPT (Invisible indexes in &&SCHEMA_NAME_UPPER)
PROMPT ============================================================

SELECT
    owner AS inv_idx_schema,
    COUNT(*) AS inv_col_count
FROM (
    SELECT
        owner,
        table_name,
        index_name AS object_name
    FROM   dba_indexes
    WHERE  owner = '&&SCHEMA_NAME_UPPER'
      AND  visibility = 'INVISIBLE'
)
GROUP BY owner
ORDER BY inv_col_count DESC, inv_idx_schema;

PROMPT

/* ****************************************************************
*  SECTION 8:  invalid_objects_report.sql
*  "Which objects are invalid in what schemas?"
*  Reports invalid database objects grouped by owner and object type
*  Run as a user with access to DBA_OBJECTS (or replace with ALL_OBJECTS/USER_OBJECTS)
******************************************************************* */

PROMPT ============================================================
PROMPT Section 8 - Invalid Objects by Schema
PROMPT ============================================================

SET PAGESIZE  60
SET LINESIZE  180
SET VERIFY    OFF
SET FEEDBACK  ON
SET TRIMSPOOL ON

COLUMN owner        HEADING 'Owner'        FORMAT A25
COLUMN object_type  HEADING 'Object Type'  FORMAT A25
COLUMN object_name  HEADING 'Object Name'  FORMAT A40
COLUMN status       HEADING 'Status'       FORMAT A10

BREAK  ON owner SKIP 1 ON object_type SKIP 1
COMPUTE COUNT OF object_name ON owner
COMPUTE COUNT OF object_name ON object_type

SELECT owner,
       object_type,
       object_name,
       status
  FROM dba_objects
 WHERE status <> 'VALID'
 AND owner = '&&SCHEMA_NAME_UPPER'
 ORDER BY owner,
          object_type,
          object_name;

CLEAR BREAKS
CLEAR COMPUTES

PROMPT
PROMPT ############################################################
PROMPT #                 END OF SCHEMA INVENTORY REPORT           #
PROMPT #                   Schema: &&SCHEMA_NAME_UPPER            #
PROMPT ############################################################

SPOOL OFF
--EXIT;  
