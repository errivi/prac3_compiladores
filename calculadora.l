%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "calculadora.tab.h"
int lineno = 1;
%}

DIGITO        [0-9]
LETRA         [a-zA-Z]
IDENTIFICADOR {LETRA}({LETRA}|{DIGITO}|_)*
ENTERO        {DIGITO}+
EXPONENTE     [eE][+-]?{ENTERO}
REAL          {ENTERO}\.{DIGITO}+({EXPONENTE})?|{ENTERO}{EXPONENTE}

%%

    /* --- Elementos a Ignorar --- */
[ \t]+          { /* Ignorar espacios */ }

    /* Comentarios tipo C++ // */
"//"            { 
    char c;
    while((c=input()) != '\n' && c != EOF); 
    lineno++; 
    return T_EOL; 
}

    /* Comentarios de bloque / * ... * / */
"/*"            { 
    char c; 
    while(1) { 
        c = input();
        if (c == '*') { 
            if ((c = input()) == '/') break; 
            else unput(c); 
        } 
        if (c == '\n') lineno++;
        if (c == 0 || c == EOF) { 
            printf("Error: Comentario no cerrado\n"); 
            exit(1); 
        } 
    } 
}

\n              { lineno++; return T_EOL; }

    /* --- Keywords  --- */
"int"           { return T_INT; }
"float"         { return T_FLOAT; }
"repeat"        { return T_REPEAT; }
"do"            { return T_DO; }     
"done"          { return T_DONE; }
"if"            { return T_IF; }
"then"          { return T_THEN; }
"fi"            { return T_FI; }
"else"          { return T_ELSE; }
"while"         { return T_WHILE; }
"until"         { return T_UNTIL; }
"for"           { return T_FOR; }
"in"            { return T_IN; }
"switch"        { return T_SWITCH; }
"case"          { return T_CASE; }
"default"       { return T_DEFAULT; }
"break"         { return T_BREAK; }
"Opcions:"      { return T_OPCIONS; }



    /* --- Literales Numéricos --- */
{REAL}          { yylval.fval = atof(yytext); return T_LIT_REAL; }
{ENTERO}        { yylval.ival = atoi(yytext); return T_LIT_ENTERO; }

    /* --- Operadores relacionales --- */
"=="            { return T_EQ; }
"!="            { return T_NE; } 
">"             { return T_GT; }
">="            { return T_GE; }
"<"             { return T_LT; }
"<="            { return T_LE; }

    /* --- Operadores Booleanos --- */
"true"          { return T_TRUE; }
"false"         { return T_FALSE; }
"and"           { return T_AND; }
"or"            { return T_OR; }
"not"           { return T_NOT; }

    /* --- Operadores Aritméticos y Asignación --- */
":="            { return T_ASSIGN; }
"+"             { return T_MAS; }
"-"             { return T_MENOS; }
"*"             { return T_POR; }
"/"             { return T_DIV; }
"%"             { return T_MOD; }
"**"            { return T_POW; }

    /* --- Puntuación --- */
"("             { return T_LPAREN; }
")"             { return T_RPAREN; }
"["             { return T_LBRACKET; } 
"]"             { return T_RBRACKET; }
"{"             { return T_LBRACE; }
"}"             { return T_RBRACE; }
";"             { return T_PCOMA; }
","             { return T_COMA; }
".."            { return T_DOTDOT; }
":"             { return T_COLON; }

    /* --- Identificadores --- */
{IDENTIFICADOR} { yylval.texto = strdup(yytext); return T_ID; }

.               { printf("Error Léxico: Caracter desconocido '%s' en línea %d\n", yytext, lineno); }

<<EOF>> {
    static int once = 0;
    
    /* Si es la primera vez que tocamos el final, devolvemos un Salto de Linea extra */
    if (once == 0) {
        once = 1;
        return T_EOL;
    }
    
    /* Si ya lo hemos devuelto, terminamos de verdad */
    yyterminate();
}
%%

int yywrap() { return 1; }