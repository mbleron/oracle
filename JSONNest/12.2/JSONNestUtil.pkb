create or replace package body JSONNestUtil is

  type jzn_nest_item is record (obj json_object_t, arr json_array_t, wrapper varchar2(4000));
  type jzn_nest_item_stack is table of jzn_nest_item;

  type jzn_nest_context is record (
    current_level    integer
  , current_obj      json_object_t
  , current_wrapper  varchar2(4000)
  , item_stack       jzn_nest_item_stack
  );
  
  type jzn_nest_context_cache is table of jzn_nest_context index by pls_integer;
  
  nest_context_cache  jzn_nest_context_cache;
  
  function createContext 
  return pls_integer
  is
  
    ctx     jzn_nest_context;
    ctx_id  pls_integer;
    
  begin
    
    ctx.item_stack := jzn_nest_item_stack();
    ctx_id := nvl(nest_context_cache.last, 1);
    nest_context_cache(ctx_id) := ctx;
    return ctx_id;
    
  end;

  
  procedure iterate (
    ctx_id in pls_integer
  , item   in JSONNestItem
  )
  is
    
    ctx              jzn_nest_context := nest_context_cache(ctx_id);
    previous_level   integer;
    tmp_obj          json_object_t;
    i                pls_integer := nvl(ctx.item_stack.last, 0);
            
    procedure push_item 
    is
    begin
      ctx.item_stack.extend;
      i := i + 1;
      ctx.item_stack(i).obj := ctx.current_obj;
      ctx.item_stack(i).arr := new json_array_t();
      ctx.item_stack(i).wrapper := ctx.current_wrapper;
    end;
    
    procedure wrap (obj in json_object_t, depth in pls_integer, finalize in boolean default false) 
    is
    begin
      if i > 0 then
        ctx.item_stack(i).arr.append(obj); 
        ctx.item_stack(i).obj.put(ctx.item_stack(i).wrapper, ctx.item_stack(i).arr);
            
        for j in 1 .. depth loop
          ctx.item_stack(i-1).arr.append(ctx.item_stack(i).obj);
          ctx.item_stack.trim;
          i := i - 1;
          if i > 1 or finalize then
            ctx.item_stack(i).obj.put(ctx.item_stack(i).wrapper, ctx.item_stack(i).arr);
          end if;
        end loop;
      end if;   
    end;
    
  begin

    previous_level := ctx.current_level;
    ctx.current_level := item.item_level;
    tmp_obj := new json_object_t(item.json_content);

    if ctx.current_level > previous_level then
            
      push_item;       
            
    elsif ctx.current_level < previous_level then
        
      wrap(ctx.current_obj, previous_level - ctx.current_level);
          
    elsif ctx.current_level = previous_level then
      
      ctx.item_stack(i).arr.append(ctx.current_obj);      
          
    end if;
      
    ctx.current_obj := tmp_obj;
    ctx.current_wrapper := item.wrapper;
    
    nest_context_cache(ctx_id) := ctx;
  
  end;
  

  function terminate (
    ctx_id in pls_integer
  )
  return clob
  is
    ctx             jzn_nest_context := nest_context_cache(ctx_id);
    i               pls_integer := nvl(ctx.item_stack.last, 0);
    previous_level  integer;
    json_content    clob;

    procedure wrap (obj in json_object_t, depth in pls_integer, finalize in boolean default false) 
    is
    begin
      if i > 0 then
        ctx.item_stack(i).arr.append(obj); 
        ctx.item_stack(i).obj.put(ctx.item_stack(i).wrapper, ctx.item_stack(i).arr);
            
        for j in 1 .. depth loop
          ctx.item_stack(i-1).arr.append(ctx.item_stack(i).obj);
          ctx.item_stack.trim;
          i := i - 1;
          if i > 1 or finalize then
            ctx.item_stack(i).obj.put(ctx.item_stack(i).wrapper, ctx.item_stack(i).arr);
          end if;
        end loop;
      end if;   
    end;

  begin

    -- flush
    previous_level := ctx.current_level;
    ctx.current_level := 2;
    wrap(ctx.current_obj, previous_level - ctx.current_level, true);
    
    if ctx.item_stack is not empty then
      json_content := ctx.item_stack(1).obj.to_clob();
    else
      json_content := ctx.current_obj.to_clob();
    end if;
    
    nest_context_cache.delete(ctx_id);
    
    return json_content;
    
  end;
  
  
  function getDocument (rc in sys_refcursor) 
  return clob
  is
    ctx_id  pls_integer;
    item    JSONNestItem := JSONNestItem(null, null, null);
  begin
    ctx_id := createContext();
    loop
      fetch rc into item.item_level, item.json_content, item.wrapper;
      exit when rc%notfound;
      iterate(ctx_id, item);
    end loop;
    close rc;
    return terminate(ctx_id);
  end;
  

end JSONNestUtil;
/
