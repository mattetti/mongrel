/**
 * Copyright (c) 2005 Zed A. Shaw
 * You can redistribute it and/or modify it under the same terms as Ruby.
 */
#include "http11_parser.h"
#include <stdio.h>
#include <assert.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>

#define LEN(AT, FPC) (FPC - buffer - parser->AT)
#define MARK(M,FPC) (parser->M = (FPC) - buffer)
#define PTR_TO(F) (buffer + parser->F)

/* For [un]escape */
#define XDIGIT_TO_NUM(h) ((h) < 'A' ? (h) - '0' : toupper(h) - 'A' + 10)
#define X2DIGITS_TO_NUM(h1, h2) ((XDIGIT_TO_NUM (h1) << 4) + XDIGIT_TO_NUM (h2))
#define XNUM_TO_DIGIT(x) ("0123456789ABCDEF"[x] + 0)
#define SAFE_CHAR(c) ( \
 ('a' <= c && c <= 'z') || \
 ('A' <= c && c <= 'Z') || \
 ('0' <= c && c <= '9') || \
 c == '$' || \
 c == '_' || \
 c == '.' || \
 c == '-' \
)

/** machine **/
%%{
  machine http_parser;

  action mark {MARK(mark, fpc); }


  action start_field { MARK(field_start, fpc); }
  action write_field { 
    parser->field_len = LEN(field_start, fpc);
  }

  action start_value { MARK(mark, fpc); }
  action write_value { 
    if(parser->http_field != NULL) {
      parser->http_field(parser->data, PTR_TO(field_start), parser->field_len, PTR_TO(mark), LEN(mark, fpc));
    }
  }
  action request_method { 
    if(parser->request_method != NULL) 
      parser->request_method(parser->data, PTR_TO(mark), LEN(mark, fpc));
  }
  action request_uri { 
    if(parser->request_uri != NULL)
      parser->request_uri(parser->data, PTR_TO(mark), LEN(mark, fpc));
  }

  action start_query {MARK(query_start, fpc); }
  action query_string { 
    if(parser->query_string != NULL)
      parser->query_string(parser->data, PTR_TO(query_start), LEN(query_start, fpc));
  }

  action http_version {	
    if(parser->http_version != NULL)
      parser->http_version(parser->data, PTR_TO(mark), LEN(mark, fpc));
  }

  action request_path {
    if(parser->request_path != NULL)
      parser->request_path(parser->data, PTR_TO(mark), LEN(mark,fpc));
  }

  action done { 
    parser->body_start = fpc - buffer + 1; 
    if(parser->header_done != NULL)
      parser->header_done(parser->data, fpc + 1, pe - fpc - 1);
    fbreak;
  }


#### HTTP PROTOCOL GRAMMAR
# line endings
  CRLF = "\r\n";

# character types
  CTL = (cntrl | 127);
  safe = ("$" | "-" | "_" | ".");
  extra = ("!" | "*" | "'" | "(" | ")" | ",");
  reserved = (";" | "/" | "?" | ":" | "@" | "&" | "=" | "+");
  unsafe = (CTL | " " | "\"" | "#" | "%" | "<" | ">");
  national = any -- (alpha | digit | reserved | extra | safe | unsafe);
  unreserved = (alpha | digit | safe | extra | national);
  escape = ("%" xdigit xdigit);
  uchar = (unreserved | escape);
  pchar = (uchar | ":" | "@" | "&" | "=" | "+");
  tspecials = ("(" | ")" | "<" | ">" | "@" | "," | ";" | ":" | "\\" | "\"" | "/" | "[" | "]" | "?" | "=" | "{" | "}" | " " | "\t");

# elements
  token = (ascii -- (CTL | tspecials));

# URI schemes and absolute paths
  scheme = ( alpha | digit | "+" | "-" | "." )* ;
  absolute_uri = (scheme ":" (uchar | reserved )*);

  path = (pchar+ ( "/" pchar* )*) ;
  query = ( uchar | reserved )* %query_string ;
  param = ( pchar | "/" )* ;
  params = (param ( ";" param )*) ;
  rel_path = (path? %request_path (";" params)?) ("?" %start_query query)?;
  absolute_path = ("/"+ rel_path);

  Request_URI = ("*" | absolute_uri | absolute_path) >mark %request_uri;
  Method = (upper | digit | safe){1,20} >mark %request_method;

  http_number = (digit+ "." digit+) ;
  HTTP_Version = ("HTTP/" http_number) >mark %http_version ;
  Request_Line = (Method " " Request_URI " " HTTP_Version CRLF) ;

  field_name = (token -- ":")+ >start_field %write_field;

  field_value = any* >start_value %write_value;

  message_header = field_name ":" " "* field_value :> CRLF;

  Request = Request_Line (message_header)* ( CRLF @done);

main := Request;
}%%

/** Data **/
%% write data;

int http_parser_init(http_parser *parser)  {
  int cs = 0;
  %% write init;
  parser->cs = cs;
  parser->body_start = 0;
  parser->content_len = 0;
  parser->mark = 0;
  parser->nread = 0;
  parser->field_len = 0;
  parser->field_start = 0;    

  return(1);
}


/** exec **/
size_t http_parser_execute(http_parser *parser, const char *buffer, size_t len, size_t off)  {
  const char *p, *pe;
  int cs = parser->cs;

  assert(off <= len && "offset past end of buffer");

  p = buffer+off;
  pe = buffer+len;

  assert(*pe == '\0' && "pointer does not end on NUL");
  assert(pe - p == len - off && "pointers aren't same distance");


  %% write exec;

  parser->cs = cs;
  parser->nread += p - (buffer + off);

  assert(p <= pe && "buffer overflow after parsing execute");
  assert(parser->nread <= len && "nread longer than length");
  assert(parser->body_start <= len && "body starts after buffer end");
  assert(parser->mark < len && "mark is after buffer end");
  assert(parser->field_len <= len && "field has length longer than whole buffer");
  assert(parser->field_start < len && "field starts after buffer end");

  if(parser->body_start) {
    /* final \r\n combo encountered so stop right here */
    %%write eof;
    parser->nread++;
  }

  return(parser->nread);
}

int http_parser_finish(http_parser *parser)
{
  int cs = parser->cs;

  %%write eof;

  parser->cs = cs;

  if (http_parser_has_error(parser) ) {
    return -1;
  } else if (http_parser_is_finished(parser) ) {
    return 1;
  } else {
    return 0;
  }
}

int http_parser_has_error(http_parser *parser) {
  return parser->cs == http_parser_error;
}

int http_parser_is_finished(http_parser *parser) {
  return parser->cs == http_parser_first_final;
}


/* returns the length of a 2 b escaped string. O(n) */
long url_escape_length(const char *s, long len)
{
  long i, escape_count = 0;
  
  for(i=0; i<len; i++)
    if(!SAFE_CHAR(s[i])) escape_count++;
  return len + 2*escape_count;
}

/* escapes a string s into a string out.
 * does not allocate memory for out. you must allocate and free this
 * string yourself. use url_escape_length() to find out how long the
 * string needs to be.
 */
void url_escape(const char *s, long len, char *out) 
{
  long i,j;
  
  for(i=0,j=0; i<len; i++) {
    if(!SAFE_CHAR(s[i])) {
      out[j++] = '%';
      out[j++] = XNUM_TO_DIGIT (s[i] >> 4);
      out[j++] = XNUM_TO_DIGIT (s[i] & 0xf);
    } else out[j++] = s[i];
  }
}

/* returns the length of a 2 b unescaped string. O(n) */
long url_unescape_length(const char *s, long len)
{
  long i, escape_count = 0;
  
  for(i=0; i < len-2; i++) {
    if(s[i] == '%' && isxdigit(s[i+1]) && isxdigit(s[i+2])) {
      i+=2;
      escape_count++;
    }
  }
  return len-2*escape_count;
}

/* unescapes URL. e.g "%21" becomes "!"  */
void url_unescape(const char *s, long len, char *out) 
{
  long i, j;
  
  for(i=0,j=0; i<len; i++,j++) {
    if(s[i] == '+') {
      out[j] = ' ';
    } else if(s[i] == '%' && i < len-2 && isxdigit(s[i+1]) && isxdigit(s[i+2])) {
      out[j] = X2DIGITS_TO_NUM(s[i+1], s[i+2]);
      i+=2;
    } else out[j] = s[i];
  }
}
