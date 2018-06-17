create or replace package JSONNestUtil is

  /*
  function getDocument (input in JSONNestItem) 
  return clob
  aggregate using JSONNestImpl;
  */

  function createContext 
  return pls_integer;
  
  procedure iterate (
    ctx_id in pls_integer
  , item   in JSONNestItem
  );
  
  function terminate (
    ctx_id in pls_integer
  )
  return clob;

end JSONNestUtil;
/
