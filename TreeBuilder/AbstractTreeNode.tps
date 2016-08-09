create or replace type AbstractTreeNode as object (
  id  integer
, member function getContent return varchar2
, member function getContentWidth return number
, member function getContentHeight return number
, member function getContentStyle return varchar2
)
not final
not instantiable
/
