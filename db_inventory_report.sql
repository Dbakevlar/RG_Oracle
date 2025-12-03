/*------------------------------------------------------------------
  db_inventory_report.sql
  Author  : Kellyn Gorman, Redgate
  Purpose  : Database inventory report for POCs
             Of non-system schemas.
  Usage    : sqlplus / as sysdba @db_inventory_report.sql
  Output   : db_inventory_<dbname>.txt in the current directory
             (the directory from which SQL*Plus was started).
-------------------------------------------------------------------*/

SET ECHO        OFF
SET FEEDBACK    ON
SET HEADING     ON
SET LINESIZE    200
SET PAGESIZE    5000
SET VERIFY      OFF
SET TRIMSPOOL   ON
SET TAB         OFF
SET TERMOUT     OFF

COLUMN db_name NEW_VALUE DB_NAME NOPRINT
SELECT LOWER(name) db_name FROM v$database;

SET TERMOUT ON

SPOOL db_inventory_&&DB_NAME..txt

TTITLE OFF
BTITLE OFF

PROMPT
PROMPT ############################################################
PROMPT #              ORACLE DATABASE INVENTORY REPORT           #
PROMPT #     Database: &&DB_NAME                                 #
PROMPT #     Generated on: &_DATE                                #
PROMPT ############################################################
PROMPT

/******************************************************************
 * Helper: list of system/Oracle-maintained schemas to exclude
 * (Extend this list as needed for your environment.)
 ******************************************************************/
-- This condition will be reused in queries via copy/paste:
--   owner NOT IN (
--     'SYS','SYSTEM','SYSMAN','DBSNMP','OUTLN','XDB','MDSYS','ORDSYS',
--     'ORDDATA','ORDPLUGINS','WMSYS','OLAPSYS','SI_INFORMTN_SCHEMA',
--     'DMSYS','EXFSYS','DVSYS','MGMT_VIEW','FLOWS_FILES',
--     'APEX_PUBLIC_USER','ANONYMOUS','XS$NULL','LBACSYS',
--     'GSMADMIN_INTERNAL','GGSYS','DVF','AUDSYS',
--     'REMOTE_SCHEDULER_AGENT','SPATIAL_WFS_ADMIN_USR',
--     'SPATIAL_CSW_ADMIN_USR','SYSBACKUP','SYSDG','SYSKM','SYSRAC'
--   )

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

PROMPT

/******************************************************************
 * SECTION 2: Total Non-System Objects
 * "How many user objects exist in this database?"
 ******************************************************************/
PROMPT ============================================================
PROMPT Section 2 - Total Non-System Objects
PROMPT (Total number of objects owned by non-system schemas)
PROMPT ============================================================

COLUMN non_system_object_count HEADING 'Non-System Object Count'

SELECT COUNT(*) AS non_system_object_count
FROM   dba_objects
WHERE  owner NOT IN (
       'SYS','SYSTEM','SYSMAN','DBSNMP','OUTLN','XDB','MDSYS','ORDSYS',
       'ORDDATA','ORDPLUGINS','WMSYS','OLAPSYS','SI_INFORMTN_SCHEMA',
       'DMSYS','EXFSYS','DVSYS','MGMT_VIEW','FLOWS_FILES',
       'APEX_PUBLIC_USER','ANONYMOUS','XS$NULL','LBACSYS',
       'GSMADMIN_INTERNAL','GGSYS','DVF','AUDSYS',
       'REMOTE_SCHEDULER_AGENT','SPATIAL_WFS_ADMIN_USR',
       'SPATIAL_CSW_ADMIN_USR','SYSBACKUP','SYSDG','SYSKM','SYSRAC'
       );

PROMPT

/******************************************************************
 * SECTION 3: Non-System Schemas and Object Counts
 * "Which user schemas exist and how many objects each owns?"
 * Notes:
 *   - Schema Type is a simple classification to help non-experts:
 *     * PERMANENT : Normal, active user schema
 *     * TEMPORARY : Temporary users
 *     * LOCKED    : Accounts currently locked
 ******************************************************************/
PROMPT ============================================================
PROMPT Section 3 - User Schemas and Their Object Counts
PROMPT (Non-system schemas with a summary of their objects)
PROMPT ============================================================

COLUMN schema_name   FORMAT A30 HEADING 'Schema Name'
COLUMN schema_type   FORMAT A10 HEADING 'Schema Type'
COLUMN object_count  FORMAT 999,999,999 HEADING 'Object Count'

SELECT
    u.username AS schema_name,
    CASE
      WHEN u.account_status LIKE 'LOCKED%' THEN 'LOCKED'
      ELSE 'PERMANENT'
    END        AS schema_type,
    COUNT(o.object_name) AS object_count
FROM   dba_users u
LEFT   JOIN dba_objects o
       ON o.owner = u.username
WHERE  u.username NOT IN (
       'SYS','SYSTEM','SYSMAN','DBSNMP','OUTLN','XDB','MDSYS','ORDSYS',
       'ORDDATA','ORDPLUGINS','WMSYS','OLAPSYS','SI_INFORMTN_SCHEMA',
       'DMSYS','EXFSYS','DVSYS','MGMT_VIEW','FLOWS_FILES',
       'APEX_PUBLIC_USER','ANONYMOUS','XS$NULL','LBACSYS',
       'GSMADMIN_INTERNAL','GGSYS','DVF','AUDSYS',
       'REMOTE_SCHEDULER_AGENT','SPATIAL_WFS_ADMIN_USR',
       'SPATIAL_CSW_ADMIN_USR','SYSBACKUP','SYSDG','SYSKM','SYSRAC'
       )
GROUP BY
    u.username,
    CASE
      WHEN u.account_status LIKE 'LOCKED%' THEN 'LOCKED'
      ELSE 'PERMANENT'
    END
ORDER BY
    schema_type,
    schema_name;

PROMPT

/******************************************************************
 * SECTION 4: Schemas Using Partitioning and Subpartitioning
 * "Which schemas use table partitioning and subpartitioning?"
 * - partitioned_table_count      : Tables that are partitioned
 * - subpartitioned_table_count   : Partitioned tables that also
 *                                  use subpartitions
 ******************************************************************/
PROMPT ============================================================
PROMPT Section 4 - Schemas Using Partitioning
PROMPT (Non-system schemas with partitioned and subpartitioned tables)
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
WHERE  owner NOT IN (
       'SYS','SYSTEM','SYSMAN','DBSNMP','OUTLN','XDB','MDSYS','ORDSYS',
       'ORDDATA','ORDPLUGINS','WMSYS','OLAPSYS','SI_INFORMTN_SCHEMA',
       'DMSYS','EXFSYS','DVSYS','MGMT_VIEW','FLOWS_FILES',
       'APEX_PUBLIC_USER','ANONYMOUS','XS$NULL','LBACSYS',
       'GSMADMIN_INTERNAL','GGSYS','DVF','AUDSYS',
       'REMOTE_SCHEDULER_AGENT','SPATIAL_WFS_ADMIN_USR',
       'SPATIAL_CSW_ADMIN_USR','SYSBACKUP','SYSDG','SYSKM','SYSRAC'
       )
GROUP BY owner
ORDER BY owner;

PROMPT

/******************************************************************
 * SECTION 5: Hidden or Invisible Objects by Schema
 * “Which schemas contain hidden or invisible objects?"
 * Here we treat as "hidden or invisible":
 *   - Hidden columns in tables (HIDDEN_COLUMN = 'YES')
 *   - Columns with internal SYS_ names
 *   - Invisible indexes (VISIBILITY = 'INVISIBLE')
 ******************************************************************/
PROMPT ============================================================
PROMPT Section 5 - Hidden or Invisible Objects by Schema
PROMPT (Non-system schemas with hidden columns or invisible indexes)
PROMPT ============================================================

COLUMN hidden_schema            FORMAT A30          HEADING 'Schema Name'
COLUMN hidden_object_count      FORMAT 999,999,999  HEADING 'Hidden/Invisible Object Count'

SELECT
    owner AS hidden_schema,
    COUNT(*) AS hidden_object_count
FROM (
    -- Hidden or internal columns
    SELECT
        owner,
        table_name,
        column_name AS object_name
    FROM   dba_tab_cols
    WHERE  (hidden_column = 'YES'
            OR column_name LIKE 'SYS\_%' ESCAPE '\')
       AND owner NOT IN (
           'SYS','SYSTEM','SYSMAN','DBSNMP','OUTLN','XDB','MDSYS','ORDSYS',
           'ORDDATA','ORDPLUGINS','WMSYS','OLAPSYS','SI_INFORMTN_SCHEMA',
           'DMSYS','EXFSYS','DVSYS','MGMT_VIEW','FLOWS_FILES',
           'APEX_PUBLIC_USER','ANONYMOUS','XS$NULL','LBACSYS',
           'GSMADMIN_INTERNAL','GGSYS','DVF','AUDSYS',
           'REMOTE_SCHEDULER_AGENT','SPATIAL_WFS_ADMIN_USR',
           'SPATIAL_CSW_ADMIN_USR','SYSBACKUP','SYSDG','SYSKM','SYSRAC'
       )
    UNION ALL
    -- Invisible indexes
    SELECT
        owner,
        table_name,
        index_name AS object_name
    FROM   dba_indexes
    WHERE  visibility = 'INVISIBLE'
       AND owner NOT IN (
           'SYS','SYSTEM','SYSMAN','DBSNMP','OUTLN','XDB','MDSYS','ORDSYS',
           'ORDDATA','ORDPLUGINS','WMSYS','OLAPSYS','SI_INFORMTN_SCHEMA',
           'DMSYS','EXFSYS','DVSYS','MGMT_VIEW','FLOWS_FILES',
           'APEX_PUBLIC_USER','ANONYMOUS','XS$NULL','LBACSYS',
           'GSMADMIN_INTERNAL','GGSYS','DVF','AUDSYS',
           'REMOTE_SCHEDULER_AGENT','SPATIAL_WFS_ADMIN_USR',
           'SPATIAL_CSW_ADMIN_USR','SYSBACKUP','SYSDG','SYSKM','SYSRAC'
       )
)
GROUP BY owner
ORDER BY hidden_object_count DESC, hidden_schema;

/******************************************************************
* SECTION 6: Invalid Objects per Schema
* - invalid_objects_report.sql
* - Reports invalid database objects grouped by owner and object type
* - This must be run with user access to DBA_OBJECTS (or replace with ALL_OBJECTS/USER_OBJECTS)
******************************************************************* */
PROMPT ============================================================
PROMPT Section 6 - Invalid Objects by Schema
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
 ORDER BY owner,
          object_type,
          object_name;

CLEAR BREAKS
CLEAR COMPUTES

PROMPT
PROMPT ############################################################
PROMPT #                 END OF INVENTORY REPORT                  #
PROMPT ############################################################

SPOOL OFF
/*SQLPlus will exit at the end of the script run.*/
--EXIT;  