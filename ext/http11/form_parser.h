#ifndef form_parser_h
#define form_parser_h

#include "http11_parser.h" // for element_cb

typedef struct form_parser {
  int error;
  void *data;
  
  element_cb pair_cb;
  element_cb key_cb;
  element_cb value_cb;
  void (*error_cb)(void *data);
} form_parser;

void form_parser_init(form_parser *parser);
size_t form_parser_execute(form_parser *parser, 
                           const char *buffer, 
                           size_t len, 
                           size_t off);

#endif