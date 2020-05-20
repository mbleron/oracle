create or replace type JSONNestImpl as object (
  ctx_id  integer
, static function ODCIAggregateInitialize (sctx in out JSONNestImpl) return number
, member function ODCIAggregateIterate (self in out JSONNestImpl, item in JSONNestItem) return number
, member function ODCIAggregateTerminate (self in JSONNestImpl, returnValue out clob, flags in number) return number
, member function ODCIAggregateMerge (self in out JSONNestImpl, sctx2 in JSONNestImpl) return number
)
/
