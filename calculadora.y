%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "semantica.h" 
#include "symtab.h"

extern int yylex();
extern int lineno;
extern char *yytext;
void yyerror(const char *s);
FILE *logfile;

void log_regla(const char *mensaje) {
    if (logfile) fprintf(logfile, "Regla: %s\n", mensaje);
}
%}

%code requires {
    #include "semantica.h"
    #include "symtab.h"
}

/* --- UNION --- */
%union {
    atributos atris;    /* Estructura para símbolos y listas de saltos */
    char* texto;        /* Identificadores */
    int ival;           /* Enteros */
    float fval;         /* Reales */
}

/* --- TOKENS --- */
%token T_EOL T_PCOMA T_COMA 
%token T_REPEAT T_DO T_DONE T_OPCIONS
%token T_LPAREN T_RPAREN T_LBRACKET T_RBRACKET 
%token T_ASSIGN

/* Control de Flujo */
%token T_IF T_THEN T_FI T_ELSE
%token T_TRUE T_FALSE T_AND T_OR T_NOT
%token T_EQ T_NE T_GT T_GE T_LT T_LE

/* Tipos de datos */
%token T_INT T_FLOAT

/* Operadores Aritméticos */
%token T_MAS T_MENOS T_POR T_DIV T_MOD T_POW

/* Tokens con valor */
%token <ival> T_LIT_ENTERO
%token <fval> T_LIT_REAL
%token <texto> T_ID

/* --- TIPOS DE RETORNO --- */
/* Todos los elementos que generan código o flujo usan 'atris' */
%type <atris> expresion termino potencia factor base
%type <atris> marcador_inicio_repeat 
%type <atris> condicion M

%type <ival> tipo declaracion

%%

/* ==========================================================================
   GRAMÁTICA PRINCIPAL
   ========================================================================== */

programa:
      seccion_opciones lista_sentencias
    | /* vacío */
    ;

seccion_opciones:
      T_OPCIONS T_EOL
    | /* vacío */
    ;

lista_sentencias:
      sentencia
    | lista_sentencias sentencia
    ;

sentencia:
      T_EOL { }
    
    /* 1. Asignación */
    | T_ID T_ASSIGN expresion T_EOL {
        log_regla("Sentencia: Asignacion");
        sem_asignar($1, $3); 
        free($1);
    }

    /* 2. Asignación a Array */
    | T_ID T_LBRACKET expresion T_RBRACKET T_ASSIGN expresion T_EOL {
        log_regla("Sentencia: Asignacion Array");
        sem_asignar_array($1, $3, $6);
        free($1);
    }

    /* 3. Impresión */
    | expresion T_EOL {
        log_regla("Sentencia: Imprimir (PUT)");
        sem_imprimir_expresion($1);
    }

    /* 4. Declaración */
    | declaracion T_EOL {
        log_regla("Sentencia: Declaración");
    }

    /* 5. REPEAT */
    | T_REPEAT expresion T_DO marcador_inicio_repeat T_EOL lista_sentencias T_DONE T_EOL {
        log_regla("Sentencia: Repeat-Do-Done");
        sem_cerrar_repeat($4.simb, $2.simb, $4.quad);
    }

    /* 6. IF-THEN (Sin Else) */
    | T_IF condicion T_THEN M T_EOL lista_sentencias T_FI T_EOL {
        log_regla("Sentencia: IF");
        /* Backpatching:
           - Si TRUE: Ir a M ($4.quad)
           - Si FALSE: Saltar al final (instrucción actual)
        */
        sem_backpatch($2.truelist, $4.quad);
        sem_backpatch($2.falselist, sem_generar_etiqueta());
    }
    
    | error T_EOL { yyerrok; }
    ;

/* --- REGLAS AUXILIARES --- */

/* Marcador M: Guarda el número de instrucción actual */
M: /* vacío */ { 
    atributos a;
    a.quad = sem_generar_etiqueta();
    /* Inicializamos resto a null/0 por seguridad */
    a.simb = NULL; a.truelist = NULL; a.falselist = NULL; a.nextlist = NULL;
    $$ = a;
}
;

marcador_inicio_repeat: 
    /* vacío */ {
        char* t_cont = sem_generar_temporal();
        sem_emitir("%s := 0", t_cont);
        
        atributos a;
        a.simb = malloc(sizeof(info_simbolo));
        a.simb->nombre = t_cont;
        a.simb->tipo = T_ENTERO;
        a.quad = sem_generar_etiqueta();
        a.truelist = NULL; a.falselist = NULL; a.nextlist = NULL;
        $$ = a;
    }
    ;

tipo:
      T_INT    { $$ = T_ENTERO; }
    | T_FLOAT  { $$ = T_REAL; }
    ;

declaracion:
      tipo T_ID {
        sem_declarar($1, $2);
        $$ = 0; 
      }
    | tipo T_ID T_LBRACKET T_LIT_ENTERO T_RBRACKET {
        sem_declarar_array($1, $2, $4);
        $$ = 0;
      }
    | declaracion T_COMA T_ID {
        sem_declarar($1, $3);
        $$ = 0;
    }
    ;

/* ==========================================================================
   EXPRESIONES BOOLEANAS Y ARITMÉTICAS
   ========================================================================== */

/* NOTA: Para esta fase, incluimos las comparaciones dentro de un no-terminal
   separado 'condicion' para usarlas en el IF. */

condicion:
      expresion T_EQ expresion { $$ = sem_operar_relacional($1, $3, "EQ"); }
    | expresion T_NE expresion { $$ = sem_operar_relacional($1, $3, "NE"); }
    | expresion T_LT expresion { $$ = sem_operar_relacional($1, $3, "LT"); }
    | expresion T_LE expresion { $$ = sem_operar_relacional($1, $3, "LE"); }
    | expresion T_GT expresion { $$ = sem_operar_relacional($1, $3, "GT"); }
    | expresion T_GE expresion { $$ = sem_operar_relacional($1, $3, "GE"); }
    ;

expresion:
      expresion T_MAS termino   { 
          log_regla("Operacion: Suma (+)");
          $$ = sem_operar_binario($1, $3, "ADDI", "ADDF"); 
      }
    | expresion T_MENOS termino { 
          log_regla("Operacion: Resta (-)");
          $$ = sem_operar_binario($1, $3, "SUBI", "SUBF"); 
      }
    | termino { $$ = $1; }
    ;

termino:
      termino T_POR potencia { 
          log_regla("Operacion: Mult (*)");
          $$ = sem_operar_binario($1, $3, "MULI", "MULF"); 
      }
    | termino T_DIV potencia { 
          log_regla("Operacion: Div (/)");
          $$ = sem_operar_binario($1, $3, "DIVI", "DIVF"); 
      }
    | termino T_MOD potencia { 
          log_regla("Operacion: Mod (%)");
          $$ = sem_operar_binario($1, $3, "MODI", "MODI"); 
      }
    | potencia { $$ = $1; }
    ;

potencia:
      factor T_POW potencia { 
          log_regla("Operacion: Pow (**)");
          $$ = sem_operar_binario($1, $3, "POW", "POW"); 
      }
    | factor { $$ = $1; }
    ;

factor:
      T_MENOS factor { 
          char* temp = sem_generar_temporal();
          if ($2.simb->tipo == T_REAL)
             sem_emitir("%s := CHSF %s", temp, $2.simb->nombre);
          else
             sem_emitir("%s := CHSI %s", temp, $2.simb->nombre);
          
          $$ = sem_crear_literal(temp, $2.simb->tipo);
      }
    | T_MAS factor   { $$ = $2; }
    | base           { $$ = $1; }
    ;

base:
      T_LIT_REAL   { 
          char buf[64];
          sprintf(buf, "%.6g", $1);
          $$ = sem_crear_literal(buf, T_REAL); 
      }
    | T_LIT_ENTERO { 
          char buf[64]; sprintf(buf, "%d", $1);
          $$ = sem_crear_literal(buf, T_ENTERO); 
      }
    | T_LPAREN expresion T_RPAREN { $$ = $2; }
    | T_ID {
        $$ = sem_obtener_simbolo($1);
        free($1);
    }
    | T_ID T_LBRACKET expresion T_RBRACKET {
        $$ = sem_acceder_array($1, $3); 
        free($1);
    }
    ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "Error [Linea %d]: %s cerca de '%s'\n", lineno, s, yytext);
    if (logfile) fprintf(logfile, "ERROR [Linea %d]: %s (Token: %s)\n", lineno, s, yytext);
}

int main(int argc, char *argv[]) {
    extern FILE *yyin;
    logfile = fopen("calculadora.log", "w");
    if (!logfile) { fprintf(stderr, "Error log\n"); return 1; }
    
    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) { perror("Error fichero"); return 1; }
        printf("Generando C3A para: %s\n", argv[1]);
    }
    
    yyparse();
    
    sem_emitir("HALT"); 
    sem_finalizar_salida(stdout);

    fclose(logfile);
    if (argc > 1) fclose(yyin);
    return 0;
}