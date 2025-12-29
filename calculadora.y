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

/* Union simplificada para C3A numérico */
%union {
    info_simbolo* info; /* Puntero a simbolo (temporal o variable) */
    char* texto;        /* Identificadores */
    int ival;           /* Literales enteros y Tipos */
    float fval;         /* Literales reales */
}

/* --- TOKENS (Sincronizados con calculadora.l) --- */
%token T_EOL T_PCOMA T_COMA 
%token T_REPEAT T_DO T_DONE T_OPCIONS
%token T_LPAREN T_RPAREN T_LBRACKET T_RBRACKET 
%token T_ASSIGN

/* Tipos de datos */
%token T_INT T_FLOAT

/* Operadores Aritméticos */
%token T_MAS T_MENOS T_POR T_DIV T_MOD T_POW

/* Tokens con valor */
%token <ival> T_LIT_ENTERO
%token <fval> T_LIT_REAL
%token <texto> T_ID

/* --- TIPOS DE RETORNO --- */
%type <info> expresion termino potencia factor base
%type <info> marcador_inicio_repeat
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
    
    /* 1. Asignación ARITMÉTICA: x := 5 + 3 */
    | T_ID T_ASSIGN expresion T_EOL {
        log_regla("Sentencia: Asignacion");
        sem_asignar($1, $3); 
        free($1);
    }

    /* 2. Asignación a ARRAY: a[i] := 5 */
    | T_ID T_LBRACKET expresion T_RBRACKET T_ASSIGN expresion T_EOL {
        log_regla("Sentencia: Asignacion Array");
        sem_asignar_array($1, $3, $6);
        free($1);
    }

    /* 3. Impresión (Expresión suelta se imprime con PUT) */
    | expresion T_EOL {
        log_regla("Sentencia: Imprimir (PUT)");
        sem_imprimir_expresion($1);
    }

    /* 4. Declaración de Variables */
    | declaracion T_EOL {
        log_regla("Sentencia: Declaración");
    }

    /* 5. Estructura de Control: REPEAT */
    | T_REPEAT expresion T_DO marcador_inicio_repeat T_EOL lista_sentencias T_DONE T_EOL {
        log_regla("Sentencia: Repeat-Do-Done");
        
        info_simbolo* tope = $2;      /* N repeticiones */
        info_simbolo* contador = $4;  /* Marcador con contador temporal */
        
        if (contador) {
            /* Recuperamos la etiqueta de inicio guardada en el contador */
            int etiqueta_inicio = contador->u.valor_int;
            sem_cerrar_repeat(contador, tope, etiqueta_inicio);
            
            free(contador->nombre);
            free(contador);
        }
    }
    
    | error T_EOL { yyerrok; }
    ;

/* --- REGLAS AUXILIARES --- */

/* Inicializa el contador del bucle y guarda la etiqueta de inicio */
marcador_inicio_repeat: 
    /* vacío */ {
        /* Generamos temporal $tXX */
        char* t_cont = sem_generar_temporal();
        
        /* Emitimos $tXX := 0 */
        sem_emitir("%s := 0", t_cont);
        
        /* Preparamos estructura para pasar info arriba */
        info_simbolo* info = malloc(sizeof(info_simbolo));
        if (info) {
            info->nombre = t_cont;
            info->tipo = T_ENTERO;
            /* Guardamos etiqueta L (siguiente instrucción) */
            info->u.valor_int = sem_generar_etiqueta(); 
        }
        $$ = info;
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
        log_regla("Declaración Array");
        $$ = 0;
      }
    | declaracion T_COMA T_ID {
        sem_declarar($1, $3);
        $$ = 0;
    }
    ;

/* ==========================================================================
   EXPRESIONES ARITMÉTICAS
   ========================================================================== */

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
          /* Unario simple */
          $$ = $2; 
      }
    | T_MAS factor   { $$ = $2; }
    | base           { $$ = $1; }
    ;

base:
      T_LIT_REAL   { 
          char buf[64]; sprintf(buf, "%.6g", $1);
          $$ = sem_crear_literal(buf, T_REAL); 
      }
    | T_LIT_ENTERO { 
          char buf[64]; sprintf(buf, "%d", $1);
          $$ = sem_crear_literal(buf, T_ENTERO); 
      }
    | T_LPAREN expresion T_RPAREN { $$ = $2; }
    
    /* Variable Simple */
    | T_ID {
        $$ = sem_obtener_simbolo($1);
        free($1);
    }

    /* Acceso a Array (Lectura) */
    | T_ID T_LBRACKET expresion T_RBRACKET {
        log_regla("Uso de Array");
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
    
    fprintf(logfile, "--- Inicio Analisis C3A ---\n");
    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) { perror("Error fichero"); return 1; }
        printf("Generando C3A para: %s\n", argv[1]);
    }
    
    yyparse();
    
    fprintf(logfile, "--- Fin Analisis ---\n");
    printf("\tHALT\n"); 
    fclose(logfile);
    if (argc > 1) fclose(yyin);
    return 0;
}