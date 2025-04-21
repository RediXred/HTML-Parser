%{
#include <stdio.h>
#include <string.h>
#include "y.tab.h"

#define TOKEN(type) return type

extern YYSTYPE yylval;
void yyerror(const char *msg);

int rawtag = 0;
%}

%option noyywrap
%option yylineno

%x COMMENT
%x RAWTEXT
%x TAGSEC
%x INATTR

WHITESPACE [ \t\r\f\v\a]+
NEWLINE \n
COMMENT_START "<!--"

%%

{WHITESPACE} {}
{NEWLINE} {}

"<!DOCTYPE"[ \t\n]*"html"[ \t\n]*">" { yylval.str = strdup("<!DOCTYPE html>"); TOKEN(DCTP); }
"<!DOCTYPE"[ \t\n]*"HTML"[ \t\n]*">" { yylval.str = strdup("<!DOCTYPE html>"); TOKEN(DCTP); }

{COMMENT_START} { BEGIN(COMMENT); }
<COMMENT>{
    "-->"    { BEGIN(INITIAL); } 
    \n       {}
    .        {}
    <<EOF>>  { 
        yyerror("Unclosed comment"); 
        return 0; 
    }
}

<INITIAL>{

    "<"[a-zA-Z] {
        unput(yytext[1]);
        
        BEGIN(TAGSEC);
        return OT;
        
    }

    "</" {
        yylval.str = strdup("</");
        BEGIN(TAGSEC);
        return OST;
    }

    "<" {
        yylval.str = strdup("<");
        return TXT;
    }

    [^<>\n]+ {
        yylval.str = strdup(yytext);
        return TXT;
    }

    ">" {
        yylval.str = strdup(">");
        return TXT;
    }
}

<RAWTEXT>{
    "</style>"   { 
        BEGIN(INITIAL); 
        rawtag = 0; 
        yylval.str = strdup("</");
        yylval.str = strdup("style");
        return CT; 
    }
    "</script>"   { 
        BEGIN(INITIAL); 
        rawtag = 0; 
        yylval.str = strdup("</");
        yylval.str = strdup("script");
        return CT; 
    }
    "</xml>"   { 
        BEGIN(INITIAL); 
        rawtag = 0; 
        yylval.str = strdup("</");
        yylval.str = strdup("xml");
        return CT; 
    }
    .|\n         {}
}

<TAGSEC>{
    [a-zA-Z][a-zA-Z0-9\-]* {
        
        printf("TAG: %s\n", yytext);
        if (strcmp(yytext, "style")==0 || strcmp(yytext, "script")==0 || strcmp(yytext, "xml")==0){
            rawtag = 1;
            printf("RAW\n");
            /*BEGIN(RAWTEXT);*/
        }
        yylval.str = strdup(yytext);
        BEGIN(INATTR);
        return NTAG;
    }

    "/>" {
        BEGIN(INITIAL);
        return SCT;
    }

    ">" {
        BEGIN(INITIAL);
        return CT;
    }

    [ \t\r\n]+ {}

    . {
        yyerror("Unsupported characters in tag section.");
        return 0;
    }
}

<INATTR>{
    [a-zA-Z_:][a-zA-Z0-9_\-.:]* {
        printf("ATTR: %s\n", yytext);
        yylval.str = strdup(yytext);
        return ATTR_NAME;
    }

    "=" { return ATTR_ASSIGN; }

    "\""[^"]*"\"" {
        printf("VAL: %s\n", yytext);
        yylval.str = strdup(yytext);
        return ATTR_VALUE;
    }

    "'"[^']*"'" {
        yylval.str = strdup(yytext);
        return ATTR_VALUE;
    }

    "/>" {
        BEGIN(INITIAL);
        return SCT;
    }

    ">" {
        if (rawtag) {
            BEGIN(RAWTEXT);
        }
        else {
            BEGIN(INITIAL);
            return CT;
        }
    }

    [ \t\r\n]+ {}

    . {
        yyerror("Unsupported characters in attribute section.");
        return 0;
    }
}

%%
