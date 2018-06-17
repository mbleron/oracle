create or replace type JSONNestItem as object (
  item_level   integer
, json_content varchar2(32767)
, wrapper      varchar2(4000)
)
/
