#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <assert.h>
#include <ctype.h> /* for toupper(), isxdigit() */
#include "form_parser.h"


%%{
  machine form;
  
  action mark_start { tokstart = p; }
  action mark_end { tokend = p; }
  action value { parser->value_cb(parser->data, tokstart, tokend-tokstart); }
  action key { parser->key_cb(parser->data, tokstart, tokend-tokstart); }
  action pair { parser->pair_cb(parser->data, tokstart, tokend-tokstart); }
  action error { parser->error_cb(parser->data); }
  
  rb = '%5D'i; # right bracket
  lb = '%5B'i; # left bracket
  pairSep = '&'; # | ' ' | ';';
  string = ( any - (pairSep | '\0') )+ >mark_start %mark_end;
  keyString = string -- (lb|'=');
  bracketed = (lb (""|keyString) :>> rb) %key;
  key = (keyString %key) bracketed*;
  pair = (key ('=' string? %value)?) %pair;
  # TODO: can the below statement be any cleaner?
  form = pairSep* pair? (pairSep+ pair)* pairSep* '\0' %err(error);
  
main := form;
}%%

%% write data;

size_t form_parser_execute(parser, buffer, len, off)
  form_parser *parser;
  const char *buffer;
  size_t len, off;
{
  const char *p, *pe;
  const char *tokstart, *tokend;
  int cs = 0;
  size_t nread;
  %% write init;
  
  /* NOTE: include nul in input stream  */
  len += 1;
  
  assert(off <= len && "offset past end of buffer");
    
  p = buffer+off;
  pe = buffer+len;
  
  /* NOTE: include nul in input stream  */
  assert(*(pe-1) == '\0' && "pointer does not end on NUL");
  assert(pe - p == len - off && "pointers aren't same distance");
  
  %% write exec;
  %% write eof;
  
  nread = p - (buffer + off);
  
  assert(p <= pe && "buffer overflow after parsing execute");
  assert(nread <= len && "nread longer than length");
  
  return(nread);
}
