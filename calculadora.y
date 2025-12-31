%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
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
%token T_WHILE T_UNTIL
%token T_FOR T_IN T_DOTDOT
%token T_SWITCH T_CASE T_DEFAULT T_BREAK T_COLON
%token T_LPAREN T_RPAREN T_LBRACKET T_RBRACKET T_LBRACE T_RBRACE
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
%type <atris> expresion termino potencia factor base
%type <atris> condicion M N
%type <atris> cond_or cond_and cond_not cond_rel
%type <atris> for_header
%type <atris> lista_casos caso default_caso
%type <atris> inicio_caso

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

/* 5. REPEAT con OPTIMIZACIÓN (Loop Unrolling) */
    | T_REPEAT expresion T_DO { 
        /* 1. ANTES del cuerpo: Empezamos a grabar */
        sem_start_record(); 
      } 
      T_EOL lista_sentencias T_DONE T_EOL {
        log_regla("Sentencia: Repeat Optimizado");
        
        /* 2. DESPUÉS del cuerpo: Paramos y recuperamos el texto */
        char* cuerpo = sem_stop_record();
        
        /* 3. Análisis: ¿Es un literal entero pequeño (<= 5)? */
        int es_literal = 0;
        int repeticiones = 0;
        
        /* Si el nombre del símbolo empieza por dígito, es un literal */
        if (isdigit($2.simb->nombre[0])) {
             es_literal = 1;
             repeticiones = atoi($2.simb->nombre);
        }

        /* --- CAMINO A: OPTIMIZACIÓN (Unrolling) --- */
        if (es_literal && repeticiones > 0 && repeticiones <= 5) {
             // Simplemente pegamos el código N veces
             for (int k = 0; k < repeticiones; k++) {
                 sem_emitir_bloque(cuerpo);
             }
        } 
        /* --- CAMINO B: BUCLE ESTÁNDAR (Dinámico) --- */
        else {
             
             // 1. Crear contador temporal y asignar 0
             atributos contador = sem_crear_temporal(T_ENTERO);
             atributos cero = sem_crear_literal("0", T_ENTERO);
             sem_asignar(contador.simb->nombre, cero);
             
             // 2. Etiqueta de inicio del bucle
             int etiqueta_inicio = sem_generar_etiqueta();
             
             // 3. Condición de salida: contador < expresion
             atributos cond = sem_operar_relacional(contador, $2, "LT");
             
             // 4. Si la condición es FALSA, saltar al final (Exit)
             int etiqueta_cuerpo = sem_generar_etiqueta();
             sem_backpatch(cond.truelist, etiqueta_cuerpo); // Si TRUE, entra al cuerpo
             
             // 5. Inyectar el cuerpo grabado
             sem_emitir_bloque(cuerpo);
             
             // 6. Incrementar contador: contador := contador + 1
             atributos uno = sem_crear_literal("1", T_ENTERO);
             atributos suma = sem_operar_binario(contador, uno, "ADDI", "ADDF");
             sem_asignar(contador.simb->nombre, suma);
             
             // 7. Saltar al inicio para comprobar condición
             sem_emitir("GOTO %d", etiqueta_inicio);
             
             // 8. Etiqueta final (Backpatching del False)
             sem_backpatch(cond.falselist, sem_generar_etiqueta());
        }
        
        free(cuerpo);
    }

    /* 6. IF-THEN (Sin Else) */
    | T_IF condicion T_THEN M T_EOL lista_sentencias T_FI T_EOL {
        log_regla("Sentencia: IF");
        sem_backpatch($2.truelist, $4.quad);
        sem_backpatch($2.falselist, sem_generar_etiqueta());
    }

    /* 7. IF-THEN-ELSE */
    | T_IF condicion T_THEN M T_EOL lista_sentencias N T_ELSE M T_EOL lista_sentencias T_FI T_EOL {
        log_regla("Sentencia: IF-ELSE");
        
        /* $2: condicion, $4: M(then), $7: N(salto fin), $9: M(else) */
        
        sem_backpatch($2.truelist, $4.quad);   /* True -> Then */
        sem_backpatch($2.falselist, $9.quad);  /* False -> Else */
        
        int final = sem_generar_etiqueta();
        sem_backpatch($7.nextlist, final);     /* Fin Then -> Final */
    }

    /* 8. WHILE: while M cond do M sentencias done */
    | T_WHILE M condicion T_DO M T_EOL { sem_init_break_layer(); } lista_sentencias T_DONE T_EOL {
        log_regla("Sentencia: WHILE");
        /* $2 (M1): Etiqueta inicio Condición (para volver atrás)
           $3 (cond): La condición con sus listas true/false
           $5 (M2): Etiqueta inicio Cuerpo
        */
        sem_backpatch($3.truelist, $5.quad);

        /* 1. Primero emitimos el salto para volver arriba */
        sem_emitir("GOTO %d", $2.quad);

        /* 2. Generamos la etiqueta de salida (sig_instruccion libre) */
        /* y rellenamos los saltos falsos para que vengan aquí. */
        int etiqueta_salida = sem_generar_etiqueta();
        sem_backpatch($3.falselist, etiqueta_salida);

        /* mandamoslos breaks a la salida */
        sem_close_break_layer(etiqueta_salida);

    }

    /* 9. DO-UNTIL: do M sentencias until cond */
    | T_DO M T_EOL { sem_init_break_layer(); } lista_sentencias T_UNTIL condicion T_EOL {
        log_regla("Sentencia: DO-UNTIL");
        /* $2 (M): Etiqueta inicio Cuerpo
           $6 (cond): Condición de salida
        */

        /* Lógica UNTIL: Repetir mientras sea FALSO.
           - Si FALSE: Vuelve al inicio ($2).
           - Si TRUE: Sale (siguiente instrucción).
        */
        
        sem_backpatch($7.falselist, $2.quad); // Vuelve atrás
        int etiqueta_salida = sem_generar_etiqueta();
        sem_backpatch($7.truelist, etiqueta_salida); // Sale

        /* mandamoslos breaks a la salida */
        sem_close_break_layer(etiqueta_salida);
    }

    /* 10. FOR: Usa la cabecera auxiliar */
    | for_header T_EOL { sem_init_break_layer(); } lista_sentencias T_DONE T_EOL {
        log_regla("Sentencia: FOR");
        
        /* Recuperamos la información de la cabecera ($1) */
        info_simbolo* iterador = $1.simb;
        int etiqueta_inicio = $1.quad;
        lista_nodos* salida = $1.falselist;
        
        /* 5. Incremento Automático: iterador := iterador + 1 */
        /* Reconstruimos atributos para poder usar sem_operar_binario */
        atributos at_iter; at_iter.simb = iterador;
        atributos at_uno = sem_crear_literal("1", T_ENTERO);
        
        /* Generamos la suma */
        atributos suma = sem_operar_binario(at_iter, at_uno, "ADDI", "ADDF");
        
        /* Asignamos el resultado a la variable iteradora */
        sem_asignar(iterador->nombre, suma);
        
        /* 6. Volver al inicio (Check condición) */
        sem_emitir("GOTO %d", etiqueta_inicio);
        
        /* 7. Rellenar la salida (Backpatching del False de la condición) */
        int etiqueta_salida = sem_generar_etiqueta();
        sem_backpatch(salida, etiqueta_salida);

        /* mandamoslos breaks a la salida */
        sem_close_break_layer(etiqueta_salida);
    }

    /* 11. SWITCH (Asegúrate de que esta regla está aquí) */
    | T_SWITCH expresion T_LBRACE T_EOL { sem_push_switch($2.simb->nombre); } 
      lista_casos 
      T_RBRACE T_EOL {
        log_regla("Sentencia: SWITCH");
        sem_pop_switch();
        
        /* Backpatching de la salida */
        int etiqueta_salida = sem_generar_etiqueta();
        sem_backpatch($6.nextlist, etiqueta_salida);

        /* mandamoslos breaks a la salida */
        sem_close_break_layer(etiqueta_salida);
    }

    /* 13. BREAK EXPLÍCITO */
    | T_BREAK {
        log_regla("Sentencia: BREAK");
        sem_add_break();
    }
    
    | error T_EOL { yyerrok; }
    ;

/* lista_casos: Gestiona la recursividad de 'case ... case ... default' */
/* Devolvemos una lista de 'salidas' (breaks) para rellenar al final del switch */

lista_casos:
    caso lista_casos { 
          /* Fusionamos las listas de break de este caso con los siguientes */
          atributos res;
          res.nextlist = sem_merge($1.nextlist, $2.nextlist);
          $$ = res;
    }
    | default_caso { $$ = $1; }
    | /* vacío */ { 
        atributos a; a.nextlist = NULL; $$ = a; 
    }
    ;

/* Regla auxiliar: Genera el IF *antes* de procesar el cuerpo */
inicio_caso:
    T_CASE T_LIT_ENTERO T_COLON T_EOL {
        char* var_switch = sem_get_switch_var();
        char num[20]; sprintf(num, "%d", $2);
        
        /* 1. Emitimos la comprobación: IF var != num GOTO [siguiente] */
        int instr_check = sem_emitir("IF %s NE %s GOTO", var_switch, num);
        
        /* Devolvemos la lista con este salto pendiente para rellenarlo luego */
        atributos res;
        res.truelist = sem_makelist(instr_check); 
        $$ = res;
    }
    ;

caso:
    inicio_caso lista_sentencias {
        /* $1 contiene el salto del IF pendiente */
        
        /* 2. Terminamos el cuerpo con un salto al FINAL del switch */
        int instr_salida = sem_emitir("GOTO");
        
        /* 3. Ahora que hemos acabado el cuerpo, sabemos dónde empieza el siguiente caso.
              Hacemos Backpatch del IF ($1) para que salte AQUÍ si la condición falló. */
        sem_backpatch($1.truelist, sem_generar_etiqueta());
        
        atributos res;
        res.nextlist = sem_makelist(instr_salida);
        $$ = res;
    }
    ;

default_caso:
    T_DEFAULT T_COLON T_EOL lista_sentencias {
        /* No genera salidas pendientes (cae al final) */
        atributos res; res.nextlist = NULL; $$ = res;
    }
    ;

/* --- REGLAS AUXILIARES --- */

/* Marcador M: Guarda posición actual */
M: /* vacío */ { 
    atributos a;
    a.quad = sem_generar_etiqueta();
    a.simb = NULL; a.truelist = NULL; a.falselist = NULL; a.nextlist = NULL;
    $$ = a;
}
;

/* Marcador N: Genera GOTO y guarda posición */
N: /* vacío */ {
    int instr = sem_emitir("GOTO");
    atributos a;
    a.nextlist = sem_makelist(instr);
    a.simb = NULL; a.truelist = NULL; a.falselist = NULL; a.quad = 0;
    $$ = a;
}
;

/* Regla auxiliar para configurar la cabecera del FOR */
for_header:
    T_FOR T_ID T_IN expresion T_DOTDOT expresion T_DO {
        /* 1. Inicialización: variable := inicio */
        sem_asignar($2, $4);
        
        /* 2. Etiqueta INICIO (para volver aquí tras cada iteración) */
        int etiqueta_inicio = sem_generar_etiqueta();
        
        /* 3. Condición: variable <= fin */
        /* Recuperamos el símbolo de la variable iteradora */
        atributos id_atrs = sem_obtener_simbolo($2);
        
        /* Generamos la comparación LE (Less or Equal) */
        atributos cond = sem_operar_relacional(id_atrs, $6, "LE");
        
        /* 4. Gestión de Saltos */
        /* TRUE: Si es menor o igual, entra al cuerpo (siguiente instrucción) */
        sem_backpatch(cond.truelist, sem_generar_etiqueta());
        
        /* FALSE: Si es mayor, debe salir. Guardamos esta lista para el final. */
        
        /* Empaquetamos todo para devolverlo a la regla principal */
        atributos res;
        res.quad = etiqueta_inicio;      // Para el GOTO de vuelta
        res.falselist = cond.falselist;  // Para el GOTO de salida
        res.simb = id_atrs.simb;         // Guardamos el puntero al ID para incrementarlo luego
        
        $$ = res;
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

condicion:
      cond_or { $$ = $1; }
    ;

cond_or:
      cond_or T_OR M cond_and {
          log_regla("Operacion: OR");
          sem_backpatch($1.falselist, $3.quad);
          atributos res;
          res.truelist = sem_merge($1.truelist, $4.truelist);
          res.falselist = $4.falselist;
          $$ = res;
      }
    | cond_and { $$ = $1; }
    ;

cond_and:
      cond_and T_AND M cond_not {
          log_regla("Operacion: AND");
          sem_backpatch($1.truelist, $3.quad);
          atributos res;
          res.truelist = $4.truelist;
          res.falselist = sem_merge($1.falselist, $4.falselist);
          $$ = res;
      }
    | cond_not { $$ = $1; }
    ;

cond_not:
      T_NOT cond_not {
          log_regla("Operacion: NOT");
          atributos res;
          res.truelist = $2.falselist;
          res.falselist = $2.truelist;
          $$ = res;
      }
    | T_LPAREN condicion T_RPAREN { $$ = $2; }
    | cond_rel { $$ = $1; }
    ;

cond_rel:
      expresion T_EQ expresion { $$ = sem_operar_relacional($1, $3, "EQ"); }
    | expresion T_NE expresion { $$ = sem_operar_relacional($1, $3, "NE"); }
    | expresion T_LT expresion { $$ = sem_operar_relacional($1, $3, "LT"); }
    | expresion T_LE expresion { $$ = sem_operar_relacional($1, $3, "LE"); }
    | expresion T_GT expresion { $$ = sem_operar_relacional($1, $3, "GT"); }
    | expresion T_GE expresion { $$ = sem_operar_relacional($1, $3, "GE"); }
    | T_TRUE { 
        atributos res; 
        int instr = sem_emitir("GOTO"); 
        res.truelist = sem_makelist(instr); 
        res.falselist = NULL; 
        $$ = res; 
    }
    | T_FALSE { 
        atributos res; 
        int instr = sem_emitir("GOTO"); 
        res.falselist = sem_makelist(instr); 
        res.truelist = NULL; 
        $$ = res; 
    }
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