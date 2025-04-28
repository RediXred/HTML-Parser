%{
#ifdef _WIN32
#include <io.h>
#define isatty _isatty
#endif
#include <stdio.h>
#include <string.h>
#include "y.tab.hpp"
#include <string>
#include <stack>
#include <iostream>
#define TOKEN(type) return type
extern YYSTYPE yylval;
void yyerror(const char *msg);

int rawtag = 0;
extern std::stack<std::string> tstack;
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
        rawtag = 0; 
        if (!tstack.empty()) {
            std::string expected = tstack.top();
            tstack.pop();
            std::string ntag = "style";
            if (expected != ntag) {
                yyerror(("Mismatched tag </" + ntag + ">, expected </" + expected + ">").c_str());
            }
        }
        BEGIN(INITIAL);
    }
    "</script>"   { 
        rawtag = 0; 
        if (!tstack.empty()) {
            std::string expected = tstack.top();
            tstack.pop();
            std::string ntag = "script";
            if (expected != ntag) {
                yyerror(("Mismatched tag </" + ntag + ">, expected </" + expected + ">").c_str());
            }
        }
        BEGIN(INITIAL);
    }
    "</xml>"   { 
        rawtag = 0; 
        if (!tstack.empty()) {
            std::string expected = tstack.top();
            tstack.pop();
            std::string ntag = "xml";
            if (expected != ntag) {
                yyerror(("Mismatched tag </" + ntag + ">, expected </" + expected + ">").c_str());
            }
        }
        BEGIN(INITIAL);
    }
    "</code>"   { 
        rawtag = 0; 
        if (!tstack.empty()) {
            std::string expected = tstack.top();
            tstack.pop();
            std::string ntag = "code";
            if (expected != ntag) {
                yyerror(("Mismatched tag </" + ntag + ">, expected </" + expected + ">").c_str());
            }
        }
        BEGIN(INITIAL);
    }
    .|\n         {}
}

<TAGSEC>{
    [a-zA-Z][a-zA-Z0-9\-]* {
        
        //printf("TAG: %s\n", yytext);
        if (strcmp(yytext, "style")==0 || strcmp(yytext, "script")==0 || strcmp(yytext, "xml")==0 || strcmp(yytext, "code")==0 ){
            rawtag = 1;
            //printf("RAW\n");
            /*BEGIN(RAWTEXT);*/
        }
        yylval.str = strdup(yytext);
        BEGIN(INATTR);
        return NTAG;
    }

    "/>" {
        BEGIN(INITIAL);
        yylval.str = strdup("/>");
        return SCT;
    }

    ">" {
        BEGIN(INITIAL);
        yylval.str = strdup(">");
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
        //printf("ATTR: %s\n", yytext);
        yylval.str = strdup(yytext);
        return ATTR_NAME;
    }

    "=" { return ATTR_ASSIGN; }

    "\""[^"]*"\"" {
        //printf("VAL: %s\n", yytext);
        yylval.str = strdup(yytext);
        return ATTR_VALUE;
    }

    "'"[^']*"'" {
        yylval.str = strdup(yytext);
        return ATTR_VALUE;
    }

    "/>" {
        BEGIN(INITIAL);
        yylval.str = strdup("/>");
        return SCT;
    }

    ">" {
        if (rawtag) {
            yylval.str = strdup(">");
            BEGIN(RAWTEXT);
            return CT;
        }
        else {
            yylval.str = strdup(">");
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
