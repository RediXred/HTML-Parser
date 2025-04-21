%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int yylex();
extern int yylineno;
extern FILE *yyin;
void yyerror(const char *s);
%}

%union {
    char *str;
    void *node;
    void *attr;
}

%token OT CT ATTR_ASSIGN ATTR_VALUE
%token DCTP
%token SCT
 
%token <str> NTAG ATTR_NAME TXT OST

%type <node> start elems elem struct_tag struct_open struct_ins struct_close
%type <attr> attrs attr

%start start

%%

start: { $$ = NULL; }
    | DCTP { $$ = NULL; }
    | DCTP elems { $$ = NULL; }
    ;

elems:
    elem { $$ = $1; }
    | elems elem { $$ = $1; }
    ;

elem:
    struct_tag { $$ = $1; }
    | TXT { $$ = $1; }
    ;

struct_tag:
    struct_open struct_ins struct_close {}
    ;

struct_open:
    OT NTAG {}
    | OST NTAG {}
    ;

struct_ins: {}
    | attrs {}
    ;

struct_close:
    CT {}
    | SCT {}
    ;

attrs:
    attr { $$ = $1; }
    | attrs attr { $$ = $1; }
    ;

attr:
    ATTR_NAME ATTR_ASSIGN ATTR_VALUE { $$ = NULL; }
    | ATTR_NAME { free($1); $$ = NULL; }
    ;

%%


int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <input_html_file>\n", argv[0]);
        return 1;
    }
    yyin = fopen(argv[1], "r");
    if (!yyin) {
        fprintf(stderr, "Error: Cannot open file '%s'\n", argv[1]);
        return 1;
    }
    int parse_result = yyparse();
    fclose(yyin);
    if (parse_result == 0) {
        fprintf(stdout, "Parsing successful\n");
    } else {
        fprintf(stderr, "Parsing failed\n");
    }
    return parse_result;
}

void yyerror(const char *s) {
    fprintf(stderr, "Error at line %d: %s\n", yylineno, s);
}