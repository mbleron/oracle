create or replace package CSXReader authid current_user is

  procedure setDebug (p_enable in boolean);
  function getXML (p_csx in blob) return clob;
  function getXMLType (p_csx in blob) return xmltype;

end CSXReader;
/
create or replace package body CSXReader is

  POW16_4           constant integer := 65536; 
  POW16_8           constant integer := 4294967296;
  POW16_12          constant integer := 281474976710656;

  DATSTR1           constant raw(1) := hextoraw('00');
  DATSTR64          constant raw(1) := hextoraw('3F');
  
  DATAL2            constant raw(1) := hextoraw('8A');
  DATAL8            constant raw(1) := hextoraw('8B');
  DATEMPT           constant raw(1) := hextoraw('8F');
  DOC               constant raw(1) := hextoraw('9E');
  STRTSEC           constant raw(1) := hextoraw('9F');
  ENDSEC            constant raw(1) := hextoraw('A0');
  CDATA1            constant raw(1) := hextoraw('A6');
  CDATA2            constant raw(1) := hextoraw('A7');
  CDATA8            constant raw(1) := hextoraw('A8');
  PI1L1             constant raw(1) := hextoraw('A9');
  PI2L4             constant raw(1) := hextoraw('AA');
  CMT1              constant raw(1) := hextoraw('AB');
  CMT2              constant raw(1) := hextoraw('AC');  
  CMT8              constant raw(1) := hextoraw('AD');  
  DEFPFX4           constant raw(1) := hextoraw('B2');
  DEFPFX8           constant raw(1) := hextoraw('B3');  
  PRPT2L1           constant raw(1) := hextoraw('C0');
  PRPT2L2           constant raw(1) := hextoraw('C1');
  PRPT4L1           constant raw(1) := hextoraw('C2');
  PRPT4L2           constant raw(1) := hextoraw('C3');  
  PRPT8L1           constant raw(1) := hextoraw('C4');
  PRPT8L2           constant raw(1) := hextoraw('C5');
  
  PRPSTT2           constant raw(1) := hextoraw('C8');
  PRPSTT4           constant raw(1) := hextoraw('C9');
  PRPSTT8           constant raw(1) := hextoraw('CA');
  PRPSTT2V          constant raw(1) := hextoraw('D2');
  PRPSTT4V          constant raw(1) := hextoraw('D3');
  PRPSTT8V          constant raw(1) := hextoraw('D4');
  ELMSTART          constant raw(1) := hextoraw('D5');
  ARRBEG            constant raw(1) := hextoraw('D7');
  ARREND            constant raw(1) := hextoraw('D8');
  ENDPRP            constant raw(1) := hextoraw('D9');
  NMSPC             constant raw(1) := hextoraw('DD');
  
  FL_STNDLN_EX      constant raw(2) := hextoraw('0001'); -- 00000000 00000001
  FL_PROLOG         constant raw(2) := hextoraw('0002'); -- 00000000 00000010
  FL_ENCODING       constant raw(2) := hextoraw('0004'); -- 00000000 00000100
  FL_XMLVERSION     constant raw(2) := hextoraw('0008'); -- 00000000 00001000
  FL_STANDALONE     constant raw(2) := hextoraw('0010'); -- 00000000 00010000
  FL_IGNOREWS       constant raw(2) := hextoraw('0020'); -- 00000000 00100000

  C_ATTR_FLAG       constant raw(1) := hextoraw('01');
  C_NO_NAMESPACE    constant raw(1) := hextoraw('07');
  
  QnameIdTable      constant varchar2(34) := xdb.dbms_csx_admin.QnameIdTable;
  NamespaceIdTable  constant varchar2(34) := xdb.dbms_csx_admin.NamespaceIdTable;
  
  -- DB Constants
  DB_CSID           constant pls_integer := nls_charset_id('CHAR_CS');
  DB_CHARSET        constant varchar2(30) := nls_charset_name(DB_CSID);
  IANA_CHARSET      constant varchar2(30) := utl_i18n.map_charset(DB_CHARSET, flag => utl_i18n.ORACLE_TO_IANA);
  
  type r_nmspcdata is record (pfx varchar2(255), uri varchar2(2000));
  -- namespace-info by prefix-id
  type t_nmspclist is table of r_nmspcdata index by binary_integer;
  
  -- prefix-id by nstoken-id
  type t_nmspcmap is table of binary_integer index by varchar2(16);
  
  type r_token is record (qname varchar2(2000), is_attr boolean default false, is_array boolean);
  type t_tokenstack is table of r_token;
  
  nmspclist       t_nmspclist;
  nmspcmap        t_nmspcmap;
  elemstack       t_tokenstack;
  
  debug_mode      boolean := false;

  procedure setDebug (p_enable in boolean)
  is
  begin
    debug_mode := p_enable;
  end;

  procedure debug (msg in varchar2) 
  is
  begin
    if debug_mode then
      dbms_output.put_line(msg);
    end if;
  end;
  
  procedure push_token (p_token in r_token, p_is_array in boolean default false) 
  is
    l_token  r_token := p_token;
  begin
    l_token.is_array := p_is_array;
    elemstack.extend();
    elemstack(elemstack.last) := l_token;
  end; 
  
  function pop_token return r_token 
  is
    l_token  r_token;
  begin
    l_token := elemstack(elemstack.last);
    elemstack.trim();
    return l_token;
  end;

  procedure pop_token 
  is
  begin
    elemstack.trim();
  end;
  
  function peek_token return r_token 
  is
    l_token  r_token;
  begin
    if elemstack is not empty then 
      l_token := elemstack(elemstack.last);
    end if;
    return l_token;
  end;
  
  function ltrimbyte (p_data in raw) 
  return raw 
  deterministic
  is
    c_nil   constant raw(1) := hextoraw('00');
    i       binary_integer := 1;
  begin
    while utl_raw.substr(p_data, i, 1) = c_nil loop
      i := i + 1;
    end loop;
    return utl_raw.substr(p_data, i);
  end;
  
  procedure define_pfx (
    p_id       in binary_integer
  , p_pfx      in varchar2
  , p_token_id in raw
  )
  is
    l_token_id    raw(8) := ltrimbyte(p_token_id);
    l_token_id_x  varchar2(16) := rawtohex(l_token_id);
    l_query       varchar2(256) := 'select nmspcuri from '||NamespaceIdTable||' where id = :1';
    l_nmspcuri    varchar2(2000);
  begin
    execute immediate l_query into l_nmspcuri using l_token_id;
    nmspclist(p_id).pfx := p_pfx;
    nmspclist(p_id).uri := l_nmspcuri;
    if not nmspcmap.exists(l_token_id_x) then
      nmspcmap(l_token_id_x) := p_id;
    end if;
    debug('xmlns'||case when p_pfx is not null then ':'||p_pfx end||'="'||l_nmspcuri||'"');
  end;

  procedure serialize (p_csx in blob, l_xml in out nocopy clob) 
  is
    l_csx       blob := p_csx;
    l_offset    integer := 1;
    l_opcode    raw(1);
    
    l_int1      binary_integer;
    l_int2      binary_integer;
    l_int64     integer;
    l_raw       raw(1);
    l_raw2      raw(2);
    l_raw4      raw(4);
    l_raw8      raw(8);
    
    l_tmp       varchar2(32767);
    l_token     r_token;
    
    l_last      varchar2(2000);
    
    idx         binary_integer;
    tag_open    boolean := false;
    array_open  boolean := false;
    
    l_buf       varchar2(32767);
    l_buflen    binary_integer := 0;
    
    procedure flush 
    is
    begin
      dbms_lob.writeappend(l_xml, l_buflen, l_buf);
    end;
    
    procedure append (p_str in varchar2) 
    is
      l_strlen  binary_integer := length(p_str);
    begin
      if l_buflen + l_strlen > 32767 then
        flush;
        l_buf := p_str;
        l_buflen := l_strlen;
      else
        l_buf := l_buf || p_str;
        l_buflen := l_buflen + l_strlen;
      end if;
    end;
    
    procedure writestr(p_str in varchar2, encode in boolean default false) 
    is
      l_str   varchar2(32767);
      c_chunk constant integer := 666;
    begin
      if p_str is not null then
        if encode then
          for i in 0 .. ceil(length(p_str)/c_chunk)-1 loop
            l_str := substr(p_str, i*c_chunk+1, c_chunk);
            l_str := dbms_xmlgen.convert(l_str, dbms_xmlgen.ENTITY_ENCODE);
            append(l_str);
          end loop;
        else
          append(p_str);
        end if;
      end if;
    end;

    procedure closetag 
    is
    begin
      if tag_open = true and not peek_token().is_attr then
        writestr('>');
        tag_open := false;
      end if;      
    end;
    
    function readbyte(n in integer) 
    return raw 
    is
      l_amount  integer := n;
      l_buf     raw(32767);
    begin
      dbms_lob.read(l_csx, l_amount, l_offset, l_buf);
      l_offset := l_offset + l_amount;
      return l_buf;
    exception
      when no_data_found then
        return null;
    end;

    function readstring(n in integer) 
    return varchar2 
    is
      l_str  varchar2(32767) := utl_i18n.raw_to_char(readbyte(n), DB_CHARSET);
    begin
      return l_str;
    end;

    function readint(n in integer) 
    return binary_integer 
    is
    begin
      return utl_raw.cast_to_binary_integer(readbyte(n));
    end;

    function readint64 
    return integer 
    is
      l_raw8  raw(8) := readbyte(8);
    begin
      return utl_raw.cast_to_binary_integer(utl_raw.substr(l_raw8,7,2))
           + utl_raw.cast_to_binary_integer(utl_raw.substr(l_raw8,5,2)) * POW16_4
           + utl_raw.cast_to_binary_integer(utl_raw.substr(l_raw8,3,2)) * POW16_8
           + utl_raw.cast_to_binary_integer(utl_raw.substr(l_raw8,1,2)) * POW16_12 ;
    end;

    function readtoken(n in integer, addpfx in boolean default true) 
    return r_token 
    is
      l_nmspcid raw(8);
      l_flags   raw(4);
      l_pfx     varchar2(255);
      l_token   r_token;
    begin
      execute immediate 'select nmspcid, localname, flags from '||QnameIdTable||' where id = :1' 
      into l_nmspcid, l_token.qname, l_flags
      using readbyte(n);
      
      l_token.is_attr := (l_flags = C_ATTR_FLAG);
      
      if l_nmspcid != C_NO_NAMESPACE then
        l_pfx := nmspclist(nmspcmap(rawtohex(ltrimbyte(l_nmspcid)))).pfx;
      end if;
      l_token.qname := case when addpfx and l_pfx is not null then l_pfx||':' end || l_token.qname;
      
      return l_token;
    end;
    
    procedure readclob (n in integer, encode in boolean default false) 
    is
      l_temp          clob;
      l_lang_context  integer := dbms_lob.default_lang_ctx;
      l_warning       integer;
      l_dest_offset   integer := 1;
    begin
      dbms_lob.createtemporary(l_temp, false);
      dbms_lob.convertToClob(
        dest_lob     => l_temp
      , src_blob     => l_csx
      , amount       => n
      , dest_offset  => l_dest_offset
      , src_offset   => l_offset
      , blob_csid    => DB_CSID
      , lang_context => l_lang_context
      , warning      => l_warning
      );
      if encode then
        l_temp := dbms_xmlgen.convert(l_temp, dbms_xmlgen.ENTITY_ENCODE);
      end if;
      dbms_lob.copy(
        dest_lob    => l_xml
      , src_lob     => l_temp
      , amount      => dbms_lob.getlength(l_temp)
      , dest_offset => dbms_lob.getlength(l_xml) + 1
      , src_offset  => 1
      );
      dbms_lob.freetemporary(l_temp);
    end;
    
    procedure writedata (len in integer, encode in boolean default false) 
    is
    begin
      if len > 32767 then
        null;
      end if;
    end;

  begin
    
    elemstack := t_tokenstack();
    
    loop
      l_opcode := readbyte(1);
      exit when l_opcode is null;
      
      if array_open and l_opcode != ARREND and l_opcode != ELMSTART then
        l_tmp := elemstack(elemstack.last).qname;
        writestr('<' || l_tmp || '>');
      end if;
    
      if l_opcode between DATSTR1 and DATSTR64 then
        
        closetag;
        l_int1 := utl_raw.cast_to_binary_integer(l_opcode) + 1;
        debug('DATSTR'||to_char(l_int1));
        writestr(readstring(l_int1), true);
        
      else
      
        case l_opcode
        when DATAL2 then
          closetag;
          debug('DATAL2');
          l_int1 := readint(2);
          if l_int1 > 32767 then
            readclob(l_int1, true);
          else
            writestr(readstring(l_int1), true);
          end if;

        when DATAL8 then
          closetag;
          debug('DATAL8');
          l_int64 := readint64;
          if l_int64 > 32767 then
            readclob(l_int64, true);
          else
            writestr(readstring(l_int64), true);
          end if;
          
        when DATEMPT then
          debug('DATEMPT');
          
        when DOC then
          debug('DOC');
          l_int1 := readint(1);
          l_raw2 := readbyte(2);
          if utl_raw.bit_and(l_raw2, FL_PROLOG) = FL_PROLOG then
            l_tmp := '<?xml version="1.0"';
            if utl_raw.bit_and(l_raw2, FL_ENCODING) = FL_ENCODING then
              l_tmp := l_tmp || ' encoding="' || IANA_CHARSET || '"';
            end if;
            if utl_raw.bit_and(l_raw2, FL_STNDLN_EX) = FL_STNDLN_EX then
              l_tmp := l_tmp || ' standalone="';
              if utl_raw.bit_and(l_raw2, FL_STANDALONE) = FL_STANDALONE then
                l_tmp := l_tmp || 'yes"';
              else
                l_tmp := l_tmp || 'no"';
              end if;
            end if;
            l_tmp := l_tmp || '?>';
          else
            l_tmp := null;
          end if;
          debug(l_tmp);
          writestr(l_tmp);
          
        when STRTSEC then
          debug('STRTSEC');
          l_int1 := readint(1); -- CSX version
          l_int1 := readint(1);
          
        when ENDSEC then
          debug('ENDSEC');
          
        when CDATA1 then
          closetag;
          debug('CDATA1');
          l_int1 := readint(1);
          l_tmp := '<![CDATA[' || readstring(l_int1) || ']]>';
          debug(l_tmp);
          writestr(l_tmp);
          
        when CDATA2 then
          closetag;
          debug('CDATA2');
          l_int1 := readint(2);
          writestr('<![CDATA[');
          if l_int1 > 32767 then
            readclob(l_int1);
          else
            writestr(readstring(l_int1));
          end if;
          writestr(']]>');          

        when CDATA8 then
          closetag;
          debug('CDATA8');
          l_int64 := readint64;
          writestr('<![CDATA[');
          if l_int1 > 32767 then
            readclob(l_int64);
          else
            writestr(readstring(l_int64));
          end if;
          writestr(']]>'); 
          
        when PI1L1 then
          closetag;
          debug('PI1L1');
          l_int1 := readint(1); -- (target + data) length
          l_int2 := readint(1); -- target length
          l_tmp := '<?' || readstring(l_int2) || ' ' || readstring(l_int1-l_int2) || '?>';
          debug(l_tmp);
          writestr(l_tmp);

        when PI2L4 then
          closetag;
          debug('PI2L4');
          l_int1 := readint(4);
          l_int2 := readint(2);
          writestr('<?'); 
          if l_int2 > 32767 then
            readclob(l_int2);
          else
            writestr(readstring(l_int2));
          end if;
          writestr(' ');
          l_int1 := l_int1-l_int2; -- data length
          if l_int1 > 32767 then
            readclob(l_int1);
          else
            writestr(readstring(l_int1));
          end if;       
          writestr('?>');
          
        when CMT1 then
          closetag;
          debug('CMT1');
          l_int1 := readint(1);
          l_tmp := '<!--'|| readstring(l_int1) ||'-->';
          debug(l_tmp);
          writestr(l_tmp);

        when CMT2 then
          closetag;
          debug('CMT2');
          l_int1 := readint(2);
          writestr('<!--');
          if l_int1 > 32767 then
            readclob(l_int1);
          else
            writestr(readstring(l_int1));
          end if;
          writestr('-->');

        when CMT8 then
          closetag;
          debug('CMT8');
          l_int64 := readint64;
          writestr('<!--');
          if l_int64 > 32767 then
            readclob(l_int64);
          else
            writestr(readstring(l_int64));
          end if;
          writestr('-->');
          
        when DEFPFX4 then
          debug('DEFPFX4');
          l_int1 := readint(1); -- prefix data length
          l_raw4 := readbyte(4); -- ns token id
          idx := readint(2); -- prefix id
          if l_int1 > 0 then
            l_tmp := readstring(l_int1); -- prefix data
          else
            l_tmp := null;
          end if;
          define_pfx(idx, l_tmp, l_raw4);

        when DEFPFX8 then
          debug('DEFPFX8');
          l_int1 := readint(1); -- prefix data length
          l_raw8 := readbyte(8); -- ns token id
          idx := readint(2); -- prefix id
          if l_int1 > 0 then
            l_tmp := readstring(l_int1); -- prefix data
          else
            l_tmp := null;
          end if;
          define_pfx(idx, l_tmp, l_raw8);
          
        when PRPT2L1 then
          debug('PRPT2L1');
          l_int1 := readint(1) + 1;
          l_token := readtoken(2);
          l_tmp := readstring(l_int1);
          if l_token.is_attr then
            writestr(' ' || l_token.qname || '="');
            writestr(l_tmp, true);
            writestr('"');
          else
            closetag;
            writestr('<' || l_token.qname || '>');
            writestr(l_tmp, true);
            writestr('</' || l_token.qname || '>');
            l_last := l_token.qname;
          end if;
          
        when PRPT2L2 then
          debug('PRPT2L2');
          l_int1 := readint(2); -- 2-byte data length
          l_token := readtoken(2); -- 2-byte token id
          l_tmp := readstring(l_int1);
          if l_token.is_attr then
            writestr(' ' || l_token.qname || '="');
            writestr(l_tmp, true);
            writestr('"');
          else
            closetag;
            writestr('<' || l_token.qname || '>');
            writestr(l_tmp, true);
            writestr('</' || l_token.qname || '>');
            l_last := l_token.qname;
          end if;

        when PRPT4L1 then
          debug('PRPT4L1');
          l_int1 := readint(1) + 1;
          l_token := readtoken(4);
          l_tmp := readstring(l_int1);
          if l_token.is_attr then
            writestr(' ' || l_token.qname || '="');
            writestr(l_tmp, true);
            writestr('"');
          else
            closetag;
            writestr('<' || l_token.qname || '>');
            writestr(l_tmp, true);
            writestr('</' || l_token.qname || '>');
            l_last := l_token.qname;
          end if;

        when PRPT4L2 then
          debug('PRPT4L2');
          l_int1 := readint(2); -- 2-byte data length
          l_token := readtoken(4); -- 4-byte token id
          l_tmp := readstring(l_int1);
          if l_token.is_attr then
            writestr(' ' || l_token.qname || '="');
            writestr(l_tmp, true);
            writestr('"');
          else
            closetag;
            writestr('<' || l_token.qname || '>');
            writestr(l_tmp, true);
            writestr('</' || l_token.qname || '>');
            l_last := l_token.qname;
          end if;

        when PRPT8L1 then
          debug('PRPT8L1');
          l_int1 := readint(1) + 1;
          l_token := readtoken(8);
          l_tmp := readstring(l_int1);
          if l_token.is_attr then
            writestr(' ' || l_token.qname || '="');
            writestr(l_tmp, true);
            writestr('"');
          else
            closetag;
            writestr('<' || l_token.qname || '>');
            writestr(l_tmp, true);
            writestr('</' || l_token.qname || '>');
            l_last := l_token.qname;
          end if;

        when PRPT8L2 then
          debug('PRPT8L2');
          l_int1 := readint(2); -- 2-byte data length
          l_token := readtoken(8); -- 8-byte token id
          l_tmp := readstring(l_int1);
          if l_token.is_attr then
            writestr(' ' || l_token.qname || '="');
            writestr(l_tmp, true);
            writestr('"');
          else
            closetag;
            writestr('<' || l_token.qname || '>');
            writestr(l_tmp, true);
            writestr('</' || l_token.qname || '>');
            l_last := l_token.qname;
          end if;
          
        when PRPSTT2 then
          debug('PRPSTT2');
          l_token := readtoken(2);
          if l_token.is_attr then
            l_tmp := ' ' || l_token.qname || '="';
          else
            closetag;
            l_tmp := '<' || l_token.qname;
            tag_open := true;
          end if;
          push_token(l_token);
          debug(l_tmp);
          writestr(l_tmp);

        when PRPSTT4 then
          debug('PRPSTT4');
          l_token := readtoken(4);
          if l_token.is_attr then
            l_tmp := ' ' || l_token.qname || '="';
          else
            closetag;
            l_tmp := '<' || l_token.qname;
            tag_open := true;
          end if;
          push_token(l_token);
          writestr(l_tmp);

        when PRPSTT8 then
          debug('PRPSTT8');
          l_token := readtoken(8);
          if l_token.is_attr then
            l_tmp := ' ' || l_token.qname || '="';
          else
            closetag;
            l_tmp := '<' || l_token.qname;
            tag_open := true;
          end if;
          push_token(l_token);
          writestr(l_tmp);
          
        when PRPSTT2V then
          closetag;
          debug('PRPSTT2V');
          l_int1 := readint(1); -- 1-byte length
          l_token := readtoken(2, false); -- 2-byte token id
          l_raw := readbyte(1); -- 1-byte flag
          if l_raw = hextoraw('08') then -- prefix id flag
            l_int2 := readint(l_int1); -- metadata = prefix id
          else
            raise_application_error(-20000, 'Unhandled flag in PRPSTT2V instruction');
          end if;
          l_token.qname := nmspclist(l_int2).pfx || ':' || l_token.qname;
          push_token(l_token);
          tag_open := true;
          writestr('<' || l_token.qname);

        when PRPSTT4V then
          closetag;
          debug('PRPSTT4V');
          l_raw := readbyte(1);
          l_token := readtoken(4, false);
          l_raw := readbyte(1);
          l_int1 := readint(2);
          l_token.qname := nmspclist(l_int1).pfx || ':' || l_token.qname;
          push_token(l_token);
          tag_open := true;
          writestr('<' || l_token.qname);
          
        when PRPSTT8V then
          closetag;
          debug('PRPSTT8V');
          l_raw := readbyte(1);
          l_token := readtoken(8, false);
          l_raw := readbyte(1);
          l_int1 := readint(2);
          l_token.qname := nmspclist(l_int1).pfx || ':' || l_token.qname;
          push_token(l_token);
          tag_open := true;
          writestr('<' || l_token.qname);          
        
        when ELMSTART then
          debug('ELMSTART');
          l_token := elemstack(elemstack.last);
          push_token(l_token);
          tag_open := true;
          writestr('<' || l_token.qname);
          
        when ARRBEG then
          debug('ARRBEG');
          array_open := true;
          l_token.qname := l_last;
          l_token.is_attr := false;
          push_token(l_token, true);
          continue;
          
        when ARREND then
          debug('ARREND');
          pop_token;
          
        when ENDPRP then
          debug('ENDPRP');
          l_token := pop_token();
          if l_token.is_attr then
            l_tmp := '"';
          else
            closetag;
            l_last := l_token.qname;
            l_tmp := '</' || l_last || '>';
          end if;
          debug(l_tmp);
          writestr(l_tmp);
          
          -- iterate if array mode
          if elemstack is not empty and peek_token().is_array = true then
            continue;
          end if;
          
        when NMSPC then
          debug('NMSPC');
          l_int1 := readint(2);
          l_tmp := ' xmlns'||case when nmspclist(l_int1).pfx is not null then ':'||
          nmspclist(l_int1).pfx end||'="'||nmspclist(l_int1).uri||'"';
          writestr(l_tmp);
          
        else
          debug('Unknown mnemonic : '||l_opcode);
        end case;
      
      end if;
      
      array_open := peek_token().is_array;
     
      if array_open then
        writestr('</' || peek_token().qname || '>');
      end if;
    
    end loop;
    
    flush;
  
  end;
  
  function getXML (p_csx in blob) return clob
  is
    l_xml     clob;
  begin
    dbms_lob.createtemporary(l_xml, false);
    serialize(p_csx, l_xml);
    return l_xml;
  end;

  function getXMLType (p_csx in blob) return xmltype
  is
  begin
    return xmltype(getXML(p_csx));
  end;

end CSXReader;
/
