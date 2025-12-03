/*------------------------------------------------------------------
+++This report is resource-consuming-  only run on NON-PRODUCTION databases.+++
cross_schema_usg_rpt.sql
Author  : Kellyn Gorman, Redgate
Purpose : A report showing non-system schemas that:
1) Call other non-system schemas in code
2) Have object privileges on other non-system schemas

Output : cross_schema_usage_<db>.txt in executing directory
------------------------------------------------------------------*/

SET FEEDBACK OFF
SET ECHO OFF
SET VERIFY OFF
SET HEADING ON
SET PAGESIZE 5000
SET LINESIZE 200
SET TRIMSPOOL ON
SET TAB OFF
SET TERMOUT OFF

COLUMN db_name NEW_VALUE DB_NAME NOPRINT
SELECT LOWER(name) db_name FROM v$database;

SET TERMOUT ON

SPOOL cross_schema_usage_&&DB_NAME..txt

PROMPT
PROMPT ==============================================================
PROMPT CROSS-SCHEMA ANALYSIS REPORT
PROMPT ==============================================================
PROMPT Database : &&DB_NAME
PROMPT Generated: &_DATE
PROMPT Description:
PROMPT This report identifies where non-system schemas:
PROMPT 1) Reference other schemas directly in PL/SQL / views
PROMPT 2) Have object-level permissions on other schemas
PROMPT ==============================================================

/*******************************************************************
SECTION 1 - Cross-schema Calls in Code
********************************************************************/
PROMPT
PROMPT --------------------------------------------------------------
PROMPT SECTION 1 - SCHEMA REFERENCES IN CODE
PROMPT --------------------------------------------------------------
PROMPT This section shows one schema directly calling another
PROMPT schema from code using explicit object references.
PROMPT Format: SCHEMA_A -> SCHEMA_B = number of objects involved
PROMPT

COLUMN calling_schema FORMAT A25 HEADING 'Calling Schema'
COLUMN referenced_schema FORMAT A25 HEADING 'Referenced Schema'
COLUMN object_count FORMAT 999,999 HEADING 'Objects Found'

WITH non_sys_users AS (
SELECT username
FROM dba_users
WHERE username NOT IN (
'SYS','SYSTEM','SYSMAN','DBSNMP','OUTLN','XDB','MDSYS','ORDSYS',
'ORDDATA','ORDPLUGINS','WMSYS','OLAPSYS','SI_INFORMTN_SCHEMA',
'DMSYS','EXFSYS','DVSYS','MGMT_VIEW','FLOWS_FILES',
'APEX_PUBLIC_USER','ANONYMOUS','XS$NULL','LBACSYS',
'GSMADMIN_INTERNAL','GGSYS','DVF','AUDSYS',
'REMOTE_SCHEDULER_AGENT','SPATIAL_WFS_ADMIN_USR',
'SPATIAL_CSW_ADMIN_USR','SYSBACKUP','SYSDG','SYSKM','SYSRAC'
)
)
SELECT
s.owner AS calling_schema,
u.username AS referenced_schema,
COUNT(DISTINCT s.name) AS object_count
FROM dba_source s
JOIN non_sys_users u_src ON s.owner = u_src.username
JOIN non_sys_users u ON u.username <> s.owner
WHERE UPPER(s.text) LIKE '%' || u.username || '.%'
GROUP BY s.owner, u.username
ORDER BY 1,2;

PROMPT

/*******************************************************************
SECTION 2 - Cross-schema Object Privileges
********************************************************************/
PROMPT --------------------------------------------------------------
PROMPT SECTION 2 - CROSS-SCHEMA PRIVILEGES
PROMPT --------------------------------------------------------------
PROMPT This section identifies object privileges where one schema
PROMPT explicitly has access to objects owned by another schema.
PROMPT

COLUMN grantee_schema FORMAT A25 HEADING 'Grantee Schema'
COLUMN owner_schema FORMAT A25 HEADING 'Object Owner'
COLUMN privilege_type FORMAT A20 HEADING 'Privilege'
COLUMN object_count FORMAT 999,999 HEADING 'Object Count'

WITH non_sys_users AS (
SELECT username
FROM dba_users
WHERE username NOT IN (
'SYS','SYSTEM','SYSMAN','DBSNMP','OUTLN','XDB','MDSYS','ORDSYS',
'ORDDATA','ORDPLUGINS','WMSYS','OLAPSYS','SI_INFORMTN_SCHEMA',
'DMSYS','EXFSYS','DVSYS','MGMT_VIEW','FLOWS_FILES',
'APEX_PUBLIC_USER','ANONYMOUS','XS$NULL','LBACSYS',
'GSMADMIN_INTERNAL','GGSYS','DVF','AUDSYS',
'REMOTE_SCHEDULER_AGENT','SPATIAL_WFS_ADMIN_USR',
'SPATIAL_CSW_ADMIN_USR','SYSBACKUP','SYSDG','SYSKM','SYSRAC'
)
)
SELECT
p.grantee AS grantee_schema,
p.owner AS owner_schema,
p.privilege AS privilege_type,
COUNT(*) AS object_count
FROM dba_tab_privs p
WHERE p.grantee IN (SELECT username FROM non_sys_users)
AND p.owner IN (SELECT username FROM non_sys_users)
AND p.grantee <> p.owner
GROUP BY p.grantee, p.owner, p.privilege
ORDER BY 1,2,3;

PROMPT

/*******************************************************************
SECTION 3 - Summary View
********************************************************************/
PROMPT --------------------------------------------------------------
PROMPT SECTION 3 - SUMMARY MATRIX
PROMPT --------------------------------------------------------------
PROMPT This shows how many other schemas each schema touches
PROMPT either via code or permissions.
PROMPT

COLUMN schema FORMAT A30
COLUMN schemas_touched FORMAT 999

WITH code_refs AS (
SELECT s.owner AS caller, u.username AS target
FROM dba_source s
JOIN dba_users u
ON UPPER(s.text) LIKE '%' || u.username || '.%'
WHERE s.owner != u.username
),
priv_refs AS (
SELECT grantee AS caller, owner AS target
FROM dba_tab_privs
WHERE grantee != owner
),
combined AS (
SELECT DISTINCT caller, target FROM code_refs
UNION
SELECT DISTINCT caller, target FROM priv_refs
)
SELECT caller AS schema,
COUNT(DISTINCT target) AS schemas_touched
FROM combined
GROUP BY caller
ORDER BY schemas_touched DESC;

PROMPT
PROMPT ==============================================================
PROMPT END OF REPORT
PROMPT ==============================================================
SPOOL OFF
--EXIT
