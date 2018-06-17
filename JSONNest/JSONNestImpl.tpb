create or replace type body JSONNestImpl is

  static function ODCIAggregateInitialize(
    sctx in out JSONNestImpl
  )
  return number 
  is
    ctx_id  pls_integer := JSONNestUtil.createContext();
  begin
    sctx := JSONNestImpl(ctx_id);
    return ODCIConst.Success;
  end;

  member function ODCIAggregateIterate(
    self in out JSONNestImpl
  , item in     JSONNestItem
  ) 
  return number 
  is
  begin
    JSONNestUtil.iterate(self.ctx_id, item);
    return ODCIConst.Success;   
  end;

  member function ODCIAggregateTerminate (
    self        in  JSONNestImpl
  , returnValue out clob
  , flags       in  number
  )
  return number
  is
  begin
    returnValue := JSONNestUtil.terminate(self.ctx_id);
    return ODCIConst.Success;
  end;

  member function ODCIAggregateMerge(
    self  in out JSONNestImpl
  , sctx2 in     JSONNestImpl
  ) 
  return number 
  is
  begin
    -- unsupported
    return ODCIConst.Error;
  end;
  
end;
/
