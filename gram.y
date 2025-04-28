%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <regex>
#include <stack>

extern int yylex();
extern int yylineno;
extern FILE *yyin;
void yyerror(const char *s);
void yyWarn(const char *s);


struct TagSt {
    std::vector<std::string> attributes;
    std::vector<std::string> parents;
    bool self_closing = false;
};

struct AttrSt {
    std::string type;
    std::vector<std::string> values;
    std::string regex_pattern;
    std::regex regex;
};

std::unordered_map<std::string, TagSt> tags_db;
std::unordered_map<std::string, AttrSt> attrs_db;

std::stack<std::string> tstack;

bool html_opened = false;
bool html_closed = false;
bool head_opened = false;
bool body_opened = false;
bool in_body = false;

bool title_opened = false;
bool header_opened = false;
bool footer_opened = false;
bool main_opened = false;

bool warns = false;
%}

%union {
    char *str;
    void *attr;
    struct {
        char *tag_name;
    } tag_info;
}

%token OT ATTR_ASSIGN 
%token DCTP
 
%token <str> NTAG ATTR_NAME TXT OST CT SCT ATTR_VALUE

%type <attr> attr
%type <str>  struct_close start elems elem struct_tag
%type <tag_info> struct_open attrs struct_ins
%start start

%%

start:
    DCTP { $$ = NULL; }
    | DCTP elems { $$ = NULL; }
    | { yyerror("There is no <!DOCTYPE html> in file!"); YYABORT; }
    ;

elems:
    elem { $$ = $1; }
    | elems elem { $$ = $1; }
    ;

elem:
    struct_tag { $$ = $1; }
    | TXT { 
        if (!in_body) {
            yyerror("Text content is only allowed inside <body> or in <head>");
        }
        $$ = $1; 
    }
    ;

struct_tag:
    struct_open struct_close {
        std::string ntag = $1.tag_name;
        free($1.tag_name);
        if (!strcmp($2, "/>")) {
            if (tags_db[ntag].self_closing == 0) {
                yyerror(("Tag <" + ntag + "/> must not be self-closing").c_str());
            }
        }
        $$ = NULL;
    }
    ;

struct_open:
    OT NTAG struct_ins {
        std::string ntag = $2;
        //free($2);
        
        if (tags_db.find(ntag) == tags_db.end()) {
            yyerror(("Unknown tag: " + ntag).c_str());
        }
        
        if (ntag == "html") {
            if (html_opened) {
                yyerror("Duplicate <html> tag");
            }
            if (!tstack.empty()) {
                yyerror("<html> must be the root element");
            }
            html_opened = true;
        } 
        else if (ntag == "head") {
            if (!html_opened || html_closed) {
                yyerror("<head> must be inside <html>");
            }
            if (head_opened) {
                yyerror("Duplicate <head> tag");
            }
            if (body_opened) {
                yyerror("<head> must come before <body>");
            }
            head_opened = true;
            in_body = true;
        }
        else if (ntag == "body") {
            if (!html_opened || html_closed) {
                yyerror("<body> must be inside <html>");
            }
            if (body_opened) {
                yyerror("Duplicate <body> tag");
            }
            body_opened = true;
            in_body = true;
        }
        else if (ntag == "title") {
            if (!head_opened) {
                yyerror("<title> must be inside <head>");
            }
            if (title_opened) {
                yyerror("Duplicate <title> tag");
            }
            title_opened = true;
        }
        else if (ntag == "main") {
            if (!body_opened) {
                yyerror("<main> must be inside <body>");
            }
            if (main_opened) {
                yyerror("Duplicate <main> tag");
            }
            main_opened = true;
        }
                

        if (!tstack.empty()) {
            std::string parent = tstack.top();
            if (!tags_db[ntag].parents.empty() &&
                std::find(tags_db[ntag].parents.begin(), 
                          tags_db[ntag].parents.end(), parent) == tags_db[ntag].parents.end()) {
                yyWarn(("Tag <" + ntag + "> not allowed inside <" + parent + ">").c_str());
            }
        } else {
            std::string parent = "DOC";
            if (!tags_db[ntag].parents.empty() &&
                std::find(tags_db[ntag].parents.begin(), 
                          tags_db[ntag].parents.end(), parent) == tags_db[ntag].parents.end()) {
                yyWarn(("Tag <" + ntag + "> not allowed inside <" + parent + ">").c_str());
            }
        }
        if (tags_db.find(ntag) != tags_db.end() && !tags_db[ntag].self_closing) {
            tstack.push(ntag);
        }
        $$.tag_name = strdup(ntag.c_str());
    }
    | OST NTAG {
        std::string ntag($2);
        free($2);
        if (ntag == "html") {
            html_closed = true;
            if (!body_opened) {
                yyerror("<body> is required before closing <html>");
            }
            in_body = false;
        }
        else if (ntag == "body" || ntag == "head") {
            in_body = false;
        }
        if (tstack.empty()) {
            yyerror(("Unexpected closing tag </" + ntag + ">").c_str());
        } else {
            std::string expected = tstack.top();
            tstack.pop();
            if (expected != ntag) {
                yyerror(("Mismatched tag </" + ntag + ">, expected </" + expected + ">").c_str());
            }
        }
        $$.tag_name = strdup(ntag.c_str());
    }
    ;

struct_ins: { $$.tag_name = $<tag_info>0.tag_name; }
    | attrs { $$.tag_name = $1.tag_name; }
    ;

struct_close:
    CT { $$ = $1; }
    | SCT { $$ = $1; }
    | { yyerror("Trouble with closing tag!"); }
    ;

attrs:
    attr { $$.tag_name = $<tag_info>0.tag_name; }
    | attrs attr { $$.tag_name = $1.tag_name; }
    ;

attr:
    ATTR_NAME ATTR_ASSIGN ATTR_VALUE {
        std::string attr_name($1);
        std::string attr_value($3);
        free($1);
        free($3);

        std::string current_tag = $<tag_info>0.tag_name ? $<tag_info>0.tag_name : "";
        if (tags_db.find(current_tag) == tags_db.end()) {
            yyerror(("Unknown tag: " + current_tag).c_str());
        }
        bool is_data_attr = (attr_name.rfind("data-", 0) == 0);
        if (is_data_attr) {
            std::string data_suffix = attr_name.substr(5);
            if (data_suffix.empty() || !std::regex_match(data_suffix, std::regex("^[a-zA-Z0-9-]+$"))) {
                yyWarn(("Invalid data-* attribute name: " + attr_name).c_str());
            } else if (attrs_db.find("data-*") != attrs_db.end()) {
                AttrSt& rule = attrs_db["data-*"];
                if (attr_value.size() >= 2 && 
                    ((attr_value.front() == '"' && attr_value.back() == '"') ||
                     (attr_value.front() == '\'' && attr_value.back() == '\''))) {
                    attr_value = attr_value.substr(1, attr_value.size() - 2);
                }
                if (!rule.regex_pattern.empty() && !std::regex_match(attr_value, rule.regex)) {
                    yyWarn(("Value '" + attr_value + "' does not match pattern for attribute '" + attr_name + "'").c_str());
                }
            } else {
                yyWarn("No rules defined for data-* attributes");
            }
        } else {
            if (attrs_db.find(attr_name) == attrs_db.end()) {
                yyWarn(("Unknown attribute: " + attr_name).c_str());
            } else {
                bool is_allowed = false;
                if (!current_tag.empty()) {
                    //локальные аттр
                    if (!tags_db[current_tag].attributes.empty() &&
                        std::find(tags_db[current_tag].attributes.begin(),
                                  tags_db[current_tag].attributes.end(), attr_name) != tags_db[current_tag].attributes.end()) {
                        is_allowed = true;
                    }
                    //глобальные
                    if (tags_db.find("global") != tags_db.end() &&
                        std::find(tags_db["global"].attributes.begin(),
                                  tags_db["global"].attributes.end(), attr_name) != tags_db["global"].attributes.end()) {
                        is_allowed = true;
                    }
                }
                if (!is_allowed && !current_tag.empty()) {
                    yyWarn(("Attribute '" + attr_name + "' not allowed for tag <" + current_tag + ">").c_str());
                }

                if (attr_value.size() >= 2 && 
                    ((attr_value.front() == '"' && attr_value.back() == '"') ||
                     (attr_value.front() == '\'' && attr_value.back() == '\''))) {
                    attr_value = attr_value.substr(1, attr_value.size() - 2);
                }
                AttrSt& rule = attrs_db[attr_name];
                if (rule.type == "enum") {
                    if (std::find(rule.values.begin(), rule.values.end(), attr_value) == rule.values.end()) {
                        yyerror(("Invalid value '" + attr_value + "' for attribute '" + attr_name + "'").c_str());
                    }
                } else if (rule.type == "boolean") {
                    if (attr_value != "true" && attr_value != "false" && attr_value != "inherit" && !attr_value.empty()) {
                        yyerror(("Invalid boolean value '" + attr_value + "' for attribute '" + attr_name + "'").c_str());
                    }
                } else if (rule.type == "number") {
                    if (!std::regex_match(attr_value, rule.regex)) {
                        yyerror(("Invalid number value '" + attr_value + "' for attribute '" + attr_name + "'").c_str());
                    }
                } else if (rule.type == "url" || rule.type == "lang" || rule.type == "string" || rule.type == "custom") {
                    if (!rule.regex_pattern.empty() && !std::regex_match(attr_value, rule.regex)) {
                        yyerror(("Value '" + attr_value + "' does not match pattern for attribute '" + attr_name + "'").c_str());
                    }
                }
            }
        }
        $$ = NULL;
    }
    | ATTR_NAME {
        std::string attr_name($1);
        free($1);

        std::string current_tag = $<tag_info>0.tag_name ? $<tag_info>0.tag_name : "";
        if (tags_db.find(current_tag) == tags_db.end()) {
            yyerror(("Unknown tag: " + current_tag).c_str());
        }
        bool is_data_attr = (attr_name.rfind("data-", 0) == 0);

        if (is_data_attr) {
            std::string data_suffix = attr_name.substr(5);
            if (data_suffix.empty() || !std::regex_match(data_suffix, std::regex("^[a-zA-Z0-9-]+$"))) {
                yyWarn(("Invalid data-* attribute name: " + attr_name).c_str());
            } else if (attrs_db.find("data-*") == attrs_db.end()) {
                yyWarn("No rules defined for data-* attributes");
            }
        } else {
            if (attrs_db.find(attr_name) == attrs_db.end()) {
                yyWarn(("Unknown attribute: " + attr_name).c_str());
            } else {
                bool is_allowed = false;
                if (!current_tag.empty()) {
                    if (!tags_db[current_tag].attributes.empty() &&
                        std::find(tags_db[current_tag].attributes.begin(),
                                  tags_db[current_tag].attributes.end(), attr_name) != tags_db[current_tag].attributes.end()) {
                        is_allowed = true;
                    }
                    if (tags_db.find("global") != tags_db.end() &&
                        std::find(tags_db["global"].attributes.begin(),
                                  tags_db["global"].attributes.end(), attr_name) != tags_db["global"].attributes.end()) {
                        is_allowed = true;
                    }
                }
                if (!is_allowed && !current_tag.empty()) {
                    yyWarn(("Attribute '" + attr_name + "' not allowed for tag <" + current_tag + ">").c_str());
                }
                if (attrs_db[attr_name].type != "boolean") {
                    yyWarn(("Attribute '" + attr_name + "' requires a value").c_str());
                }
            }
        }
        $$ = NULL;
    }
    ;

%%

void trim(std::string& s) {
    s.erase(s.begin(), std::find_if(s.begin(), s.end(), [](int ch) {
        return !std::isspace(ch);
    }));
    s.erase(std::find_if(s.rbegin(), s.rend(), [](int ch) {
        return !std::isspace(ch);
    }).base(), s.end());
}

std::vector<std::string> split(const std::string& s, char delimiter) {
    std::vector<std::string> tokens;
    size_t start = 0, end;
    while ((end = s.find(delimiter, start)) != std::string::npos) {
        tokens.push_back(s.substr(start, end - start));
        start = end + 1;
    }
    tokens.push_back(s.substr(start));
    return tokens;
}


void parse_tags_ini(const std::string& filename) {
    std::ifstream file(filename);
    std::string line, current_section;
    
    while (std::getline(file, line)) {
        trim(line);
        if (line.empty() || line[0] == ';') continue;

        //секция
        if (line[0] == '[') {
            current_section = line.substr(1, line.find(']') - 1);
            std::transform(current_section.begin(), current_section.end(), current_section.begin(), ::tolower);
            continue;
        }
        //ключ-значение
        size_t delimiter_pos = line.find('=');
        if (delimiter_pos == std::string::npos) continue;

        std::string key = line.substr(0, delimiter_pos);
        std::string value = line.substr(delimiter_pos + 1);
        trim(key);
        trim(value);

        if (key == "attributes") {
            for (auto& attr : split(value, ',')) {
                trim(attr);
                tags_db[current_section].attributes.push_back(attr);
            }
        }
        else if (key == "parents") {
            for (auto& parent : split(value, ',')) {
                trim(parent);
                tags_db[current_section].parents.push_back(parent);
            }
        }
        else if (key == "self_closing") {
            tags_db[current_section].self_closing = (value == "1");
        }
    }
}

void parse_attr_ini(const std::string& filename) {
    std::ifstream file(filename);
    std::string line, current_attr;
    
    while (std::getline(file, line)) {
        trim(line);
        if (line.empty() || line[0] == ';') continue;

        //секция
        if (line[0] == '[') {
            current_attr = line.substr(1, line.find(']') - 1);
            continue;
        }

        //ключ-значение
        size_t delimiter_pos = line.find('=');
        if (delimiter_pos == std::string::npos) continue;

        std::string key = line.substr(0, delimiter_pos);
        std::string value = line.substr(delimiter_pos + 1);
        trim(key);
        trim(value);

        //инициализация
        if (attrs_db.find(current_attr) == attrs_db.end()) {
            attrs_db[current_attr] = AttrSt{};
        }

        if (key == "type") {
            attrs_db[current_attr].type = value;
        }
        else if (key == "values") {
            if (value.find(',') != std::string::npos) {
                for (auto& val : split(value, ',')) {
                    trim(val);
                    attrs_db[current_attr].values.push_back(val);
                }
            } else {
                attrs_db[current_attr].values.push_back(value);
            }
        }
        else if (key == "regex") {
            attrs_db[current_attr].regex_pattern = value;
            try {
                attrs_db[current_attr].regex = std::regex(value);
            } catch (const std::regex_error& e) {
                std::cerr << "Regex error for " << current_attr << ": " << e.what() << "\n";
            }
        }
    }
}


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

    parse_tags_ini("tags.ini");
    /*
    if (tags_db.count("head")) {
        auto& link = tags_db["head"];
        std::cout << "map tag rules:\n";
        std::cout << "Attributes: ";
        for (auto& attr : link.attributes) std::cout << attr << ", ";
        std::cout << std::endl << "Parents: ";
        for (auto& attr : link.parents) std::cout << attr << ", ";
        }
    }
    */
    parse_attr_ini("attr.ini");
    /*
    if (attrs_db.count("reversed")) {
        auto& href = attrs_db["reversed"];
        std::cout << "href attribute rules:\n";
        std::cout << "Type: " << href.type << "\n";
        std::cout << "Values: ";
        for (auto& v : href.values) std::cout << v << ", ";
        std::cout << "\nRegex: " << href.regex_pattern << "\n";
    }
    */
    int parse_result = yyparse();
    if (!html_opened) yyerror("Missing <html> tag");
    if (!head_opened) yyerror("Missing <head> tag");
    if (!body_opened) yyerror("Missing <body> tag");
    if (!tstack.empty()) {
        std::string msg = "Unclosed tags: ";
        while (!tstack.empty()) {
            msg += "<" + tstack.top() + "> ";
            tstack.pop();
        }
        yyerror(msg.c_str());
    }
    fclose(yyin);
    if (parse_result == 0 && !warns) {
        fprintf(stdout, "Parsing successful\n");
    } else if (warns) {
        fprintf(stdout, "Parsed with warnings\n");
    }
    else {
        fprintf(stderr, "Parsing failed\n");
    }
    return parse_result;
}

void yyerror(const char *s) {
    fprintf(stderr, "[Error at line %d]: %s\n", yylineno, s);
    fprintf(stderr, "Parsing failed\n");
    exit(-1);
}

void yyWarn(const char *s) {
    fprintf(stderr, "[Warning at line %d]: %s\n", yylineno, s);
    warns = true;
}