/* ########################################################################################
   # cross_ref_rpt.sql
...# Author: Kellyn Gorman
...# Description: Generates a cross-reference report for a specified
   #              Oracle schema, detailing synonyms, cross-schema to be run from SQL*Plus.
   #              references in PL/SQL code, and grants to other users.
   ######################################################################################## 
*/
set echo off
set verify off
set pagesize 500
set linesize 200
set trimspool on
set tab off

prompt ============================================
prompt  Cross-Reference Report for Oracle Schema
prompt ============================================

prompt "What Schema do you want to run the report for?"
accept p_schema char prompt 'Enter schema name: '


column v_schema new_value v_schema noprint
select upper('&p_schema') v_schema from dual;

set termout on
prompt
prompt Generating cross-reference report for schema &v_schema
prompt (Output file: cross_ref_&v_schema..txt)
prompt

spool cross_ref_&v_schema..txt

prompt ====================================================
prompt  CROSS-REFERENCE REPORT FOR SCHEMA &v_schema
prompt  Generated on: &&_DATE
prompt ====================================================
prompt

----------------------------------------------------------------------
-- SECTION 1: Schema Overview
----------------------------------------------------------------------

prompt  
prompt SECTION 1 - SCHEMA OVERVIEW
prompt -----------------------------------------

column username           format a20 heading 'SCHEMA'
column account_status     format a20
column created            format a20
column default_tablespace format a20 heading 'DEFAULT_TS'
column temporary_tablespace format a20 heading 'TEMP_TS'

select u.username,
       u.account_status,
       to_char(u.created,'YYYY-MM-DD HH24:MI:SS') created,
       u.default_tablespace,
       u.temporary_tablespace,
       (select count(*) from dba_tables         t where t.owner = u.username) as num_tables,
       (select count(*) from dba_views          v where v.owner = u.username) as num_views,
       (select count(*) from dba_indexes        i where i.owner = u.username) as num_indexes,
       (select count(*) from dba_sequences      s where s.sequence_owner = u.username) as num_sequences,
       (select count(*) from dba_synonyms       y where y.owner = u.username) as num_synonyms,
       (select count(*) from dba_objects        o where o.owner = u.username and o.object_type = 'PACKAGE')        as num_packages,
       (select count(*) from dba_objects        o where o.owner = u.username and o.object_type = 'PROCEDURE')      as num_procedures,
       (select count(*) from dba_objects        o where o.owner = u.username and o.object_type = 'FUNCTION')       as num_functions,
       (select count(*) from dba_triggers       tr where tr.owner = u.username)                                    as num_triggers
from   dba_users u
where  u.username = '&v_schema'
/

----------------------------------------------------------------------
-- SECTION 2: Synonyms Created in Schema &v_schema Referencing Others
----------------------------------------------------------------------

prompt
prompt SECTION 2 - SYNONYMS TO OTHER SCHEMAS
prompt -----------------------------------------

column table_owner      format a30 heading 'REFERENCED_SCHEMA'
column synonym_count    format 999,999 heading '#SYNONYMS'

select nvl(table_owner,'<UNKNOWN>') table_owner,
       count(*) synonym_count
from   dba_synonyms
where  owner = '&v_schema'
group  by table_owner
order  by table_owner
/

prompt
prompt Detail of synonyms:
prompt (OWNER = &v_schema)
prompt

column synonym_name format a30 heading 'SYNONYM'
column table_name   format a30 heading 'OBJECT_NAME'

select synonym_name,
       nvl(table_owner,'<UNKNOWN>') as table_owner,
       table_name
from   dba_synonyms
where  owner = '&v_schema'
order  by table_owner, synonym_name
/

----------------------------------------------------------------------
-- SECTION 3: Cross-Schema References in PL/SQL and Triggers
--          (Fully Qualified: SCHEMA.OBJECT)
----------------------------------------------------------------------

prompt 
prompt SECTION 3 - FULLY QUALIFIED REFERENCES TO OTHER SCHEMAS
prompt ----------------------------------------------------------

column referenced_schema   format a30 heading 'REFERENCED_SCHEMA'
column total_references    format 999,999,999 heading 'TOTAL_REFS'

with schemas as (
    select username as ref_schema
    from   dba_users
    where  username <> '&v_schema'
),
src as (
    select owner,
           type,
           name,
           line,
           upper(text) as text
    from   dba_source
    where  owner = '&v_schema'
    and    type in ('PROCEDURE','FUNCTION','PACKAGE','PACKAGE BODY','TRIGGER')
),
hits as (
    -- Count how many times each schema appears as "SCHEMA." per line
    select s.ref_schema,
           src.type,
           src.name,
           sum(
               (length(text) - length(replace(text, s.ref_schema || '.', '')))
               / (length(s.ref_schema) + 1)
           ) as refs
    from   schemas s
           join src
             on instr(src.text, s.ref_schema || '.') > 0
    group  by s.ref_schema, src.type, src.name
)
select ref_schema as referenced_schema,
       sum(refs)  as total_references
from   hits
group  by ref_schema
having sum(refs) > 0
order  by total_references desc, referenced_schema
/

prompt 
prompt Detailed references by object:
prompt -----------------------------------------

column obj_type       format a18 heading 'OBJECT_TYPE'
column obj_name       format a40 heading 'OBJECT_NAME'
column refs           format 999,999 heading '#REFS'

WITH schemas AS (
    SELECT username AS ref_schema
    FROM   dba_users
    WHERE  username <> '&v_schema'
),
src AS (
    SELECT owner,
           type,
           name,
           line,
           UPPER(text) AS text
    FROM   dba_source
    WHERE  owner = '&v_schema'
    AND    type IN ('PROCEDURE','FUNCTION','PACKAGE','PACKAGE BODY','TRIGGER')
),
hits AS (
    -- Count how many times each schema appears as "SCHEMA." per line
    SELECT s.ref_schema,
           src.type,
           src.name,
           SUM(
               (LENGTH(text) - LENGTH(REPLACE(text, s.ref_schema || '.', '')))
               / (LENGTH(s.ref_schema) + 1)
           ) AS refs
    FROM   schemas s
           JOIN src
             ON INSTR(src.text, s.ref_schema || '.') > 0
    GROUP  BY s.ref_schema, src.type, src.name
)
SELECT ref_schema  AS referenced_schema,
       type        AS obj_type,
       name        AS obj_name,
       refs
FROM   hits
WHERE  refs > 0
ORDER  BY referenced_schema, type, name
/

----------------------------------------------------------------------
-- SECTION 4: Grants from &v_schema Objects to Other Users/Roles
----------------------------------------------------------------------

prompt 
prompt SECTION 4 - GRANTS ON &v_schema OBJECTS TO OTHER PRINCIPALS
prompt --------------------------------------------------------------

column grantee       format a30 heading 'GRANTEE'
column owner         format a20 heading 'OWNER'
column table_name    format a30 heading 'OBJECT_NAME'
column grantor       format a20 heading 'GRANTOR'
column privilege     format a20 heading 'PRIVILEGE'
column type          format a15 heading 'OBJ_TYPE'
column grantable     format a9  heading 'GRANTABLE'

select owner,
       table_name,
       type,
       grantee,
       grantor,
       privilege,
       grantable
from   dba_tab_privs
where  owner = '&v_schema'
order  by table_name, grantee, privilege
/

prompt
prompt ================================
prompt  END OF REPORT FOR &v_schema
prompt ================================

spool off;

set feedback on
set verify on
set termout on
--exit;