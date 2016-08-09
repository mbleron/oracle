# TreeBuilder - a PL/SQL graphical tree generator

TreeBuilder computes the set of node coordinates necessary to represent a single-rooted tree in a graphical environment.  
Node positioning is implemented using the improved version of [Walker's algorithm](http://www.cs.unc.edu/techreports/89-034.pdf), published by Buchheim, Jünger and Leipert :  
<http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.16.8757>

Tree data is exposed as a pipelined function.  
The API also provides a constructor to visualize the tree as an SVG object.

## Installation

```
@AbstractTreeNode.tps
@BasicTreeNode.typ
@TreeBuilder.pck
```

## Usage

### Data source

TreeBuilder expects a hierarchically-ordered data source, with two mandatory columns : 
* a level indicator 
* a subclass of `AbstractTreeNode`

> `AbstractTreeNode` is an abstract object type (class). That allows custom node classes to be transparently plugged in.  
> The `BasicTreeNode` concrete class provided here is a simple implementation of `AbstractTreeNode`.

The data source is provided through a REF cursor.

<br>
### Tree properties

The following properties are available to customize the tree representation as SVG : 

| Property | Description
| :------- | :----------
| levelGap | distance between each level
| siblingGap | distance between sibling nodes
| neighborGap | distance between two neighbor subtrees at the same level
| linkStyle | style of inter-node connections - (LINK_STRAIGHT \| LINK_CUBIC_BEZIER)
| orientation | tree orientation - (ORIENT_TOP_BOTTOM \| ORIENT_LEFT_RIGHT)
| defaultStyle | CSS string, overridable at node level

<br>
### Examples


1\. Top-bottom orientation with straight connections : 

[tree1.svg](./svg/tree1.svg)
```
declare

  rc            sys_refcursor;
  svg           clob;
  defaultStyle  varchar2(4000) := 
'rect { fill: #ff0000; stroke:black }
 text { font-size:8px; font-family:verdana; stroke:none }
 line { fill:none; stroke:#000000; stroke-width:1px; stroke-linecap:round }
 path { fill:none; stroke:#000000; stroke-width:1px }';

begin

  execute immediate 'alter session set nls_numeric_characters = ".,"';
 
  open rc for
  select level
       , BasicTreeNode(
           id             => e.employee_id
         , content        => e.last_name
         , style          => 'fill:#00ff00'
         , wScalingFactor => 8
         , height         => 20
         )
  from hr.employees e
       left outer join hr.departments d on d.department_id = e.department_id
  connect by prior e.employee_id = e.manager_id
  start with e.manager_id is null;
  
  svg := TreeBuilder.getSVG(
           p_rc           => rc
         , p_defaultStyle => defaultStyle
         , p_linkStyle    => treebuilder.LINK_STRAIGHT
         , p_scale        => 2
         , p_levelGap     => 30
         , p_siblingGap   => 5
         , p_neighborGap  => 20
         , p_orientation  => treebuilder.ORIENT_TOP_BOTTOM
         );

  dbms_xslprocessor.clob2file(svg, 'TMP_DIR', 'tree1.svg');

end;
/
```
<br>
2\. Left-right orientation with Bezier connections : 

[tree2.svg](./svg/tree2.svg)
```
declare

  rc            sys_refcursor;
  svg           clob;
  defaultStyle  varchar2(4000) := 
'rect { fill: #ff0000; stroke:black }
 text { font-size:8px; font-family:verdana; stroke:none }
 line { fill:none; stroke:#000000; stroke-width:1px; stroke-linecap:round }
 path { fill:none; stroke:#000000; stroke-width:1px }';

begin

  execute immediate 'alter session set nls_numeric_characters = ".,"';
 
  open rc for
  select level
       , BasicTreeNode(
           e.empno
         , e.ename
         , 'fill:' || 
           case e.deptno 
             when 10 then 'DarkOrange'
             when 20 then 'HotPink'
             when 30 then 'LightGreen'
             else 'SkyBlue'
           end
         , wScalingFactor => 8
         , height         => 20
         )
  from scott.emp e
  connect by prior e.empno = e.mgr
  start with e.mgr is null;
  
  svg := TreeBuilder.getSVG(
           p_rc           => rc
         , p_defaultStyle => defaultStyle
         , p_linkStyle    => treebuilder.LINK_CUBIC_BEZIER
         , p_scale        => 2
         , p_levelGap     => 20
         , p_siblingGap   => 10
         , p_neighborGap  => 20
         , p_orientation  => treebuilder.ORIENT_LEFT_RIGHT
         );

  dbms_xslprocessor.clob2file(svg, 'TMP_DIR', 'tree2.svg');

end;
/
```
