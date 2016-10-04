create or replace package HModel is

  type Node is record (id integer, pid integer, name varchar2(4000));
  type Tree is table of Node;

  -- Convert Path Enumeration to Adjency List
  function getAdjencyList (
    p_rc  in sys_refcursor
  , p_sep in varchar2
  ) 
  return Tree pipelined;

end HModel;
/
create or replace package body HModel is

  type NodeMap is table of binary_integer index by varchar2(4000);
  
  function getAdjencyList (
    p_rc  in sys_refcursor
  , p_sep in varchar2
  ) 
  return Tree pipelined
  is
  
    nmap      NodeMap;
    r         Node;
    l_tmp     varchar2(4000);
    l_path    varchar2(4000);
    l_id      integer := 0;
    l_pid     integer;
    p1        binary_integer;
    p2        binary_integer;

  begin
    
    loop
      fetch p_rc into l_tmp;
      exit when p_rc%notfound;
      
      p2 := 1;
      l_pid := null;
      
      loop
        
        p1 := instr(l_tmp, p_sep, p2);
        
        if p1 = 0 then
          l_path := l_tmp;
          r.name := substr(l_path, p2);
        else
          l_path := substr(l_tmp, 1, p1 - 1);
          r.name := substr(l_path, p2);
          p2 := p1 + 1;     
        end if;
        
        if nmap.exists(l_path) then
          l_pid := nmap(l_path);
        else
          l_id := l_id + 1;
          nmap(l_path) := l_id;
          r.id := l_id;
          r.pid := l_pid;
          l_pid := l_id;
          pipe row (r);
        end if;
        
        exit when p1 = 0;
        
      end loop;

    end loop;
    
    close p_rc;   
    
    return;
    
  end;

end HModel;
/
