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

    /* --- Keywords (Solo las necesarias para C3A) --- */
"int"           { return T_INT; }
"float"         { return T_FLOAT; }
"repeat"        { return T_REPEAT; }
"do"            { return T_DO; }     
"done"          { return T_DONE; }   
"Opcions:"      { return T_OPCIONS; } 

    /* --- Literales Numéricos --- */
{REAL}          { yylval.fval = atof(yytext); return T_LIT_REAL; }
{ENTERO}        { yylval.ival = atoi(yytext); return T_LIT_ENTERO; }

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
";"             { return T_PCOMA; }
","             { return T_COMA; }

    /* --- Identificadores --- */
{IDENTIFICADOR} { yylval.texto = strdup(yytext); return T_ID; }

.               { printf("Error Léxico: Caracter desconocido '%s' en línea %d\n", yytext, lineno); }

%%

int yywrap() { return 1; }