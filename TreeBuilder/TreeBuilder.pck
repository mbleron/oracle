create or replace package TreeBuilder is

  ORIENT_TOP_BOTTOM   constant binary_integer := 0;
  ORIENT_LEFT_RIGHT   constant binary_integer := 1;
  LINK_STRAIGHT       constant binary_integer := 0;
  LINK_CUBIC_BEZIER   constant binary_integer := 1;

  subtype treeHandle is binary_integer;
  
  type nodeData is record (
    id          integer
  , pid         integer
  , lvl         integer
  , x           number
  , y           number
  , lx          number
  , ly          number
  , rx          number
  , ry          number
  , w           number
  , h           number
  , lvl_gap     number
  , xc_anchor   number
  , yc_anchor   number
  , xp_anchor   number
  , yp_anchor   number
  , x_link_dir  number
  , y_link_dir  number
  , pxc_anchor  number
  , pyc_anchor  number
  , node        AbstractTreeNode
  );  
  
  type nodeTable is table of nodeData;
  
  function newTree(
    p_rc          in sys_refcursor
  , p_levelGap    in number
  , p_siblingGap  in number
  , p_neighborGap in number
  , p_orientation in binary_integer
  ) 
  return treeHandle;
  
  function getTreeData (
    hdl in treeHandle
  ) 
  return nodeTable pipelined;
  
  procedure freeTree (
    hdl in treeHandle
  );
  
  function getSVG (
    p_rc           in sys_refcursor
  , p_defaultStyle in varchar2
  , p_linkStyle    in integer default LINK_STRAIGHT
  , p_scale        in number default 1
  , p_levelGap     in number
  , p_siblingGap   in number
  , p_neighborGap  in number
  , p_orientation  in binary_integer default ORIENT_TOP_BOTTOM
  ) 
  return clob;

end TreeBuilder;
/
create or replace package body TreeBuilder is

  type childList is table of binary_integer; 

  type nodeInfo is record (
    parent     binary_integer
  , children   childList
  , lvl        integer
  , ancestor   binary_integer
  , thread     binary_integer
  , modif      number
  , prelim     number
  , change     number
  , shift      number
  , x          number
  , y          number
  , width      number
  , height     number
  , node       AbstractTreeNode      
  );

  type nodeList is table of nodeInfo index by binary_integer;
  type levelList is table of number index by binary_integer;
  
  type treeInfo is record (
    root         binary_integer
  , nodes        nodeList
  , levels       levelList
  , levelGap     number
  , siblingGap   number
  , neighborGap  number
  , orientation  binary_integer
  );
  
  type treeCache is table of treeInfo index by treeHandle;
  
  t    treeCache;

  function is_leaf (h in treeHandle, v in binary_integer) return boolean is
  begin
    return ( t(h).nodes(v).children is empty );
  end;
  
  
  function left_sibling (h in treeHandle, v in binary_integer) return binary_integer is
    p  binary_integer := t(h).nodes(v).parent;
    w  childList;
    c  binary_integer;
  begin
    if p is not null then
      w := t(h).nodes(p).children;
      for i in 2 .. w.count loop
        if w(i) = v then
          c := w(i-1);
          exit;
        end if;
      end loop;
    end if;
    
    return c;
  end;
  
  
  function next_left (h in treeHandle, v in binary_integer) return binary_integer is
    c  binary_integer;
  begin
    if v is not null then
      if t(h).nodes(v).children is not empty then
        c := t(h).nodes(v).children(1);
      else
        c := t(h).nodes(v).thread;
      end if;
    end if;
    return c;
  end;


  function next_right (h in treeHandle, v in binary_integer) return binary_integer is
    c  binary_integer;
  begin
    if v is not null then
      if t(h).nodes(v).children is not empty then
        c := t(h).nodes(v).children(t(h).nodes(v).children.last());
      else
        c := t(h).nodes(v).thread;
      end if;
    end if;
    return c;
  end;
  
  
  function ancestor (h in treeHandle, vim in binary_integer, v in binary_integer, defaultAncestor in binary_integer) 
  return binary_integer is
    a  binary_integer := t(h).nodes(vim).ancestor;
  begin
    return case when t(h).nodes(a).parent = t(h).nodes(v).parent then a 
                else defaultAncestor 
           end;
  end;
  
  
  function num (h in treeHandle, v in binary_integer) return number is
    w  childlist := t(h).nodes(t(h).nodes(v).parent).children;
  begin
    for i in 1 .. w.count loop
      if w(i) = v then
        return i;
      end if;
    end loop;
  end;
  
  
  procedure move_subtree (h in treeHandle, wm in binary_integer, wp in binary_integer, shift in number) is
    subtrees number;
  begin
    subtrees := num(h, wp) - num(h, wm);
    t(h).nodes(wp).change := t(h).nodes(wp).change - shift/subtrees;
    t(h).nodes(wp).shift := t(h).nodes(wp).shift + shift;
    t(h).nodes(wm).change := t(h).nodes(wm).change + shift/subtrees;
    t(h).nodes(wp).prelim := t(h).nodes(wp).prelim + shift;
    t(h).nodes(wp).modif := t(h).nodes(wp).modif + shift;
  end;
  
  
  procedure apportion (h in treeHandle, v in binary_integer, defaultAncestor in out binary_integer) is
    w    binary_integer;
    vip  binary_integer;
    v0p  binary_integer;
    vim  binary_integer;
    v0m  binary_integer;
    sip  number;
    s0p  number;
    sim  number;
    s0m  number;
  
    shift number;
  
  begin
    w := left_sibling(h, v);
    if w is not null then
    
      vip := v;
      v0p := v;
      vim := w;
      v0m := t(h).nodes(t(h).nodes(vip).parent).children(1);
      sip := t(h).nodes(vip).modif;
      s0p := t(h).nodes(v0p).modif;
      sim := t(h).nodes(vim).modif;
      s0m := t(h).nodes(v0m).modif;
      
      while next_right(h, vim) is not null and next_left(h, vip) is not null loop
      
        vim := next_right(h, vim);
        vip := next_left(h, vip);
        v0m := next_left(h, v0m);
        v0p := next_right(h, v0p);
        t(h).nodes(v0p).ancestor := v;
        shift := t(h).nodes(vim).prelim + sim - t(h).nodes(vip).prelim - sip;
        
        -- <!ORIENTATION>
        case t(h).orientation 
        when ORIENT_TOP_BOTTOM then
          shift := shift + t(h).neighborGap + t(h).nodes(vim).width;
        when ORIENT_LEFT_RIGHT then
          shift := shift + ( t(h).neighborGap + t(h).nodes(vim).height );
        end case;
        
        
        if shift > 0 then
          move_subtree(h, ancestor(h, vim, v, defaultAncestor), v, shift);
          sip := sip + shift;
          s0p := s0p + shift;
        end if;
        
        sim := sim + t(h).nodes(vim).modif;
        sip := sip + t(h).nodes(vip).modif;
        s0m := s0m + t(h).nodes(v0m).modif;
        s0p := s0p + t(h).nodes(v0p).modif;
      
      end loop;
      
      if next_right(h, vim) is not null and next_right(h, v0p) is null then
        t(h).nodes(v0p).thread := next_right(h, vim);
        t(h).nodes(v0p).modif := t(h).nodes(v0p).modif + sim - s0p;
      end if;
      
      if next_left(h, vip) is not null and next_left(h, v0m) is null then
        t(h).nodes(v0m).thread := next_left(h, vip);
        t(h).nodes(v0m).modif := t(h).nodes(v0m).modif + sip - s0m;
        defaultAncestor := v;
      end if;
      
    end if;
    
  end;
  
  
  procedure execute_shifts(h in treeHandle, v in binary_integer) is
    shift  number := 0;
    change number := 0;
    w      childlist := t(h).nodes(v).children;
  begin
    for i in reverse 1 .. w.count loop
      t(h).nodes(w(i)).prelim := t(h).nodes(w(i)).prelim + shift;
      t(h).nodes(w(i)).modif := t(h).nodes(w(i)).modif + shift;
      change := change + t(h).nodes(w(i)).change;
      shift := shift + t(h).nodes(w(i)).shift + change;
    end loop;
  end;


  procedure first_walk (h in treeHandle, v in binary_integer) is
    defaultAncestor binary_integer;
    w               childlist;
    midpoint        number;
    ls              binary_integer;
  begin
    if is_leaf (h, v) then
      ls := left_sibling(h, v);
      if ls is not null then
        -- <!ORIENTATION>
        case t(h).orientation 
        when ORIENT_TOP_BOTTOM then
          t(h).nodes(v).prelim := t(h).nodes(ls).prelim + t(h).siblingGap + t(h).nodes(ls).width;
        when ORIENT_LEFT_RIGHT then
          t(h).nodes(v).prelim := t(h).nodes(ls).prelim + ( t(h).siblingGap + t(h).nodes(ls).height );
        end case;
      end if;
    else
      w := t(h).nodes(v).children;
      defaultAncestor := w(1);
      for i in 1 .. w.count loop
        first_walk(h, w(i));
        apportion(h, w(i), defaultAncestor);
      end loop;
      execute_shifts(h, v);
      
      -- <!ORIENTATION>
      case t(h).orientation 
      when ORIENT_TOP_BOTTOM then
        midpoint := ( t(h).nodes(w(1)).prelim 
                    + t(h).nodes(w(w.last())).prelim
                    + t(h).nodes(w(w.last())).width
                     )/2;
        midpoint := midpoint - t(h).nodes(v).width/2;        
      when ORIENT_LEFT_RIGHT then
        midpoint := ( t(h).nodes(w(1)).prelim 
                    + t(h).nodes(w(w.last())).prelim
                    + t(h).nodes(w(w.last())).height
                     )/2;
        midpoint := midpoint - t(h).nodes(v).height/2;        
      end case;
      
      ls := left_sibling(h, v);
      if ls is not null then
        -- <!ORIENTATION>
        case t(h).orientation 
        when ORIENT_TOP_BOTTOM then
          t(h).nodes(v).prelim := t(h).nodes(ls).prelim 
                                + t(h).siblingGap
                                + t(h).nodes(ls).width ;
        when ORIENT_LEFT_RIGHT then
          t(h).nodes(v).prelim := t(h).nodes(ls).prelim 
                                + t(h).siblingGap
                                + t(h).nodes(ls).height ;
        end case;

        t(h).nodes(v).modif := t(h).nodes(v).prelim - midpoint;
      else
        t(h).nodes(v).prelim := midpoint;
      end if;
    end if;
  end;


  procedure second_walk (h in treeHandle, v in binary_integer, m in number) is
  begin
    
    -- <!ORIENTATION>
    case t(h).orientation 
    when ORIENT_TOP_BOTTOM then
      t(h).nodes(v).x := t(h).nodes(v).prelim + m;
      t(h).nodes(v).y := t(h).levels( t(h).nodes(v).lvl );
    when ORIENT_LEFT_RIGHT then
      t(h).nodes(v).x := t(h).levels( t(h).nodes(v).lvl );
      t(h).nodes(v).y := t(h).nodes(v).prelim + m;
    end case;
    
    for i in 1 .. t(h).nodes(v).children.count loop
      second_walk(h, t(h).nodes(v).children(i), m + t(h).nodes(v).modif);
    end loop;
  end;

  
  procedure tree_layout (h in treeHandle) is
    i binary_integer;
  begin
    i := t(h).nodes.first();
    while i is not null loop
      t(h).nodes(i).modif := 0;
      t(h).nodes(i).thread := null;
      t(h).nodes(i).ancestor := i;
      t(h).nodes(i).prelim := 0;
      t(h).nodes(i).change := 0;
      t(h).nodes(i).shift := 0;
      i := t(h).nodes.next(i);
    end loop;
    first_walk(h, t(h).root);
    second_walk(h, t(h).root, -t(h).nodes(t(h).root).prelim);
  end;
  

  function newTree (
    p_rc          in sys_refcursor
  , p_levelGap    in number
  , p_siblingGap  in number
  , p_neighborGap in number
  , p_orientation in binary_integer
  ) 
  return treeHandle 
  is
    
    i                binary_integer := 0;
    node_level_prev  integer := 0;
    node_level       integer;
    -- current parent
    p                binary_integer;
    h                treeHandle;   
    node             AbstractTreeNode;
    nodeExtent       number;
    nodeLevelPos     number;

    -- local stack definition
    type stack_array is table of binary_integer;
    type stack_struct is record (top binary_integer, stack stack_array);
    st  stack_struct;
    procedure st_init is
    begin
      st.top := 0;
      st.stack := stack_array();
    end;
    procedure st_push(n in binary_integer) is
    begin
      st.stack.extend;
      st.top := st.top + 1;
      st.stack(st.top) := n;
    end;
    procedure st_pop (cnt in binary_integer default 1) is
    begin
      st.stack.trim(cnt);
      st.top := st.top - cnt;
    end;
    function st_peek return binary_integer is
    begin
      return st.stack(st.top);
    end;
    -- ------------------------------------------------

  begin
  
    h := nvl(t.last, 0) + 1;
    t(h).levelGap := p_levelGap;
    t(h).siblingGap := p_siblingGap;
    t(h).neighborGap := p_neighborGap;
    t(h).orientation := p_orientation;
    st_init;
  
    loop
     
      fetch p_rc into node_level, node;
      exit when p_rc%notfound;
      
      i := i + 1;
      
      -- new child level?
      if node_level > node_level_prev then
        st_push(p);
        if not t(h).levels.exists(node_level) then
          t(h).levels(node_level) := 0;
        end if;
      -- back x level up?
      elsif node_level < node_level_prev then
        st_pop(node_level_prev-node_level);
        p := st_peek();
      else
        p := st_peek();
      end if;  
      
      if node_level = 1 then
        t(h).root := i;
      else
        t(h).nodes(p).children.extend;
        t(h).nodes(p).children(t(h).nodes(p).children.last) := i;
      end if;
       
      t(h).nodes(i).parent := p;
      t(h).nodes(i).lvl := node_level;
      t(h).nodes(i).children := childlist();
      t(h).nodes(i).width := node.getContentWidth();
      t(h).nodes(i).height := node.getContentHeight();
      t(h).nodes(i).node := node;
      
      --<!ORIENTATION>
      case t(h).orientation
      when ORIENT_TOP_BOTTOM then
        nodeExtent := node.getContentHeight();
      when ORIENT_LEFT_RIGHT then
        nodeExtent := node.getContentWidth();
      end case;   
      if nodeExtent > t(h).levels(node_level) then
        t(h).levels(node_level) := nodeExtent;
      end if;
      
      node_level_prev := node_level;
    
      p := i;

    end loop;
    
    close p_rc;
    
    node_level := t(h).levels.first;
    nodeLevelPos := 0;
    while node_level is not null loop
      nodeExtent := t(h).levels(node_level);
      t(h).levels(node_level) := nodeLevelPos;
      nodeLevelPos := nodeLevelPos + nodeExtent + t(h).levelGap;
      node_level := t(h).levels.next(node_level);   
    end loop;

    return h;
  
  end;
  

  function getTreeData (
    hdl in treeHandle
  ) 
  return nodeTable pipelined 
  is
  
    nodes        nodeList       := t(hdl).nodes;
    levelGap     number         := t(hdl).levelGap;
    orientation  binary_integer := t(hdl).orientation;
    id           binary_integer := nodes.first();
    r            nodeData;
    lc           binary_integer;
    rc           binary_integer;
    c            number;
    
  begin
    
    while id is not null loop
      
      r.id := id;
      r.lvl := nodes(id).lvl;
      r.pid := nodes(id).parent;
      r.x := nodes(id).x;
      r.y := nodes(id).y;
      r.w := nodes(id).width;
      r.h := nodes(id).height;
      r.lvl_gap := levelGap;
      
      case orientation
      when ORIENT_TOP_BOTTOM then
        r.x_link_dir := 0;
        r.y_link_dir := 1;
      when ORIENT_LEFT_RIGHT then
        r.x_link_dir := 1;
        r.y_link_dir := 0;        
      end case;      
      
      if r.pid is not null then

        case orientation
        when ORIENT_TOP_BOTTOM then
          
          r.xp_anchor := r.x + r.w/2;
          r.yp_anchor := r.y;
          r.pxc_anchor := nodes(r.pid).x + nodes(r.pid).width/2;
          r.pyc_anchor := nodes(r.pid).y + nodes(r.pid).height;
          
        when ORIENT_LEFT_RIGHT then
          
          r.xp_anchor := r.x;
          r.yp_anchor := r.y + r.h/2;
          r.pxc_anchor := nodes(r.pid).x + nodes(r.pid).width;
          r.pyc_anchor := nodes(r.pid).y + nodes(r.pid).height/2;
          
        end case;

      end if;
      
      c := nodes(id).children.count;
      if c != 0 then
        
        lc := nodes(id).children(1);
        rc := nodes(id).children(c);
        
        case orientation
        when ORIENT_TOP_BOTTOM then
          
          r.xc_anchor := r.x + r.w/2;
          r.yc_anchor := r.y + r.h;
          r.lx := nodes(lc).x + nodes(lc).width / 2 ;
          r.ly := nodes(lc).y - levelGap/2;
          r.rx := nodes(rc).x + nodes(rc).width / 2 ;
          r.ry := nodes(rc).y - levelGap/2;  
          
        when ORIENT_LEFT_RIGHT then
          
          r.xc_anchor := r.x + r.w;
          r.yc_anchor := r.y + r.h/2;
          r.lx := nodes(lc).x - levelGap/2;
          r.ly := nodes(lc).y + nodes(lc).height / 2;
          r.rx := nodes(rc).x - levelGap/2 ;
          r.ry := nodes(rc).y + nodes(rc).height / 2; 
          
        end case; 
        
      else
        
        r.lx := null;
        r.ly := null;
        r.rx := null;
        r.ry := null;
        r.xc_anchor := null;
        r.yc_anchor := null;
        
      end if; 
          
      r.node := nodes(id).node;
      pipe row (r);
      id := nodes.next(id);
      
    end loop;
    
    return;
    
  end;


  procedure freeTree (
    hdl in treeHandle
  ) 
  is
  begin 
    t.delete(hdl);
  end;


  function getSVG (
    p_rc           in sys_refcursor
  , p_defaultStyle in varchar2
  , p_linkStyle    in integer default LINK_STRAIGHT
  , p_scale        in number default 1
  , p_levelGap     in number
  , p_siblingGap   in number
  , p_neighborGap  in number
  , p_orientation  in binary_integer default ORIENT_TOP_BOTTOM
  )
  return clob
  is
  
    output  clob;
    hdl     treeHandle;
    
  begin
    
    hdl := newTree( p_rc
                  , p_levelGap
                  , p_siblingGap
                  , p_neighborGap
                  , p_orientation );
                  
    tree_layout(hdl);

    select xmlserialize(document
             xmlelement("svg"
             , xmlattributes(
                 'http://www.w3.org/2000/svg' as "xmlns"
               , tw * p_scale as "width"
               , th * p_scale as "height"
               )
             , xmlelement("style", p_defaultStyle)
             , xmlelement("g"
               --, xmlattributes('translate(20,20)' as "transform")
               , xmlattributes('scale('||to_char(p_scale)||')' as "transform")
               , xmlagg( 
                   xmlconcat(
                     xmlelement("rect",
                       xmlattributes(
                         t.node.getContentStyle() as "style"
                       , x  as "x"
                       , y  as "y"
                       , w  as "width"
                       , h  as "height"
                       , 3  as "rx"
                       , 3  as "ry"
                       )
                     )
                   , xmlelement("text", 
                       xmlattributes(
                         x + w/2  as "x"
                       , y + h/2  as "y"
                       , 'middle' as "text-anchor"
                       , 'middle' as "dominant-baseline"
                       )
                     , t.node.getContent()
                     )
                   , case p_linkStyle
                     when LINK_STRAIGHT then
                       -- Straight links
                       xmlconcat(
                         case when pid is not null then
                           xmlelement("line",
                             xmlattributes(
                               xp_anchor - x_link_dir * lvl_gap/2 as "x1"
                             , yp_anchor - y_link_dir * lvl_gap/2 as "y1"
                             , xp_anchor as "x2"
                             , yp_anchor as "y2"
                             )
                           )
                         end
                       , case when lx is not null then
                           xmlconcat(
                             xmlelement("line",
                               xmlattributes(
                                 lx as "x1"
                               , ly as "y1"
                               , rx as "x2"
                               , ry as "y2"
                               )
                             )
                           , xmlelement("line",
                               xmlattributes(
                                 xc_anchor as "x1"
                               , yc_anchor as "y1"
                               , xc_anchor + x_link_dir * (lx - xc_anchor) as "x2"
                               , yc_anchor + y_link_dir * (ly - yc_anchor) as "y2"
                               )
                             )
                           )
                         end
                       )
                     when LINK_CUBIC_BEZIER then
                       -- Cubic Bezier path
                       case when pid is not null then
                         xmlelement("path",
                           xmlattributes(
                             'M ' || pxc_anchor || ','
                                  || pyc_anchor || ' ' ||
                             'C ' || ( pxc_anchor + x_link_dir * (lvl_gap/2) ) || ',' 
                                  || ( pyc_anchor + y_link_dir * (lvl_gap/2) ) || ' '
                                  || ( xp_anchor - x_link_dir * (lvl_gap/2) ) || ','
                                  || ( yp_anchor - y_link_dir * (lvl_gap/2) ) || ' '
                                  || xp_anchor || ','
                                  || yp_anchor
                                  as "d"
                           )
                         )
                       end
                     end -- p_linkStyle
                   ) 
                   order by x
                 ) 
               )
             )
             indent
           )
    into output
    from (
      select x - dx as x
           , y - dy as y
           , w
           , h
           , node
           , pid
           , lx - dx as lx
           , ly - dy as ly
           , rx - dx as rx
           , ry - dy as ry        
           , mx - dx as tw
           , my - dy as th
           , lvl_gap
           , xp_anchor - dx as xp_anchor
           , yp_anchor - dy as yp_anchor
           , xc_anchor - dx as xc_anchor
           , yc_anchor - dy as yc_anchor
           , x_link_dir
           , y_link_dir
           , pxc_anchor - dx as pxc_anchor
           , pyc_anchor - dy as pyc_anchor
      from ( 
        select x
             , y
             , w
             , h
             , node
             , pid
             , lx, ly
             , rx, ry        
             , xp_anchor, yp_anchor
             , xc_anchor, yc_anchor
             , pxc_anchor, pyc_anchor
             , x_link_dir, y_link_dir
             , lvl_gap
             , min(x) over() - 1 as dx
             , min(y) over() - 1 as dy
             , max(x + w) over() + 2 as mx
             , max(y + h) over() + 2 as my
        from table(getTreeData(hdl))
      )
    ) t
    group by tw, th ;
    
    freeTree(hdl);
    return output;
    
  end;

end TreeBuilder;
/
