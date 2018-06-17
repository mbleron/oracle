create or replace function JSONNest (input in JSONNestItem)
return clob
aggregate using JSONNestImpl;
/
