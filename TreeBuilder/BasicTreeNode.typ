create or replace type BasicTreeNode under AbstractTreeNode (
  content         varchar2(4000)
, style           varchar2(4000)
, wScalingFactor  number
, height          number
, overriding member function getContent return varchar2
, overriding member function getContentWidth return number
, overriding member function getContentHeight return number
, overriding member function getContentStyle return varchar2
)
not final
/
create or replace type body BasicTreeNode is

  overriding member function getContent return varchar2
  is
  begin
    return self.content;
  end;

  overriding member function getContentWidth return number
  is
  begin
    return self.wScalingFactor * length(self.content);
  end;

  overriding member function getContentHeight return number
  is
  begin
    return self.height;
  end;

  overriding member function getContentStyle return varchar2
  is
  begin
    return self.style;
  end;

end;
/
