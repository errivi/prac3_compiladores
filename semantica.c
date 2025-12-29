#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "semantica.h"

/* Contadores globales */
static int contador_temporales = 1;
static int contador_instrucciones = 1;

/* Auxiliar para crear nodos info_simbolo dinámicamente */
info_simbolo* crear_nodo_info(char* nombre, int tipo) {
    info_simbolo* nodo = malloc(sizeof(info_simbolo));
    if (nodo == NULL) { 
        fprintf(stderr, "Error fatal: Sin memoria\n"); 
        exit(1); 
    }
    nodo->nombre = strdup(nombre);
    nodo->tipo = tipo;
    nodo->u.valor_int = 0;
    return nodo;
}

/* --- GENERACIÓN C3A --- */

char* sem_generar_temporal() {
    char* temp = malloc(20);
    /* Formato: $t01, $t02... según el PDF de C3A */
    sprintf(temp, "$t%02d", contador_temporales++);
    return temp;
}

int sem_generar_etiqueta() {
    return contador_instrucciones; /* Devuelve el número de línea actual */
}

void sem_emitir(const char* fmt, ...) {
    va_list args;
    printf("%d:\n", contador_instrucciones++); /* Número de línea */
    printf("\t"); /* Indentación */
    
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    
    printf("\n");
}

/* --- FUNCIONES PRINCIPALES --- */

info_simbolo* sem_crear_literal(char* valor, int tipo) {
    return crear_nodo_info(valor, tipo);
}

info_simbolo* sem_obtener_simbolo(char* nombre) {
    sym_value_type info; /* Esto es un puntero a info_simbolo */
    
    /* sym_lookup espera la dirección donde guardar el puntero recuperado */
    if (sym_lookup(nombre, &info) == SYMTAB_NOT_FOUND) {
        char err[100];
        sprintf(err, "Variable no declarada: %s", nombre);
        yyerror(err);
        return crear_nodo_info("err", T_ERROR);
    }
    
    /* Devolvemos una NUEVA copia de la info para no alterar la tabla directamente
       si modificamos el nombre por un temporal */
    return crear_nodo_info(info->nombre, info->tipo);
}

void sem_declarar(int tipo, char* nombre) {
    /* 1. Reservamos memoria en el Heap (persistente) */
    info_simbolo* nodo = malloc(sizeof(info_simbolo));
    nodo->tipo = tipo;
    nodo->nombre = strdup(nombre);
    nodo->u.valor_int = 0;

    /* 2. sym_add espera 'sym_value_type *', que es 'info_simbolo **' */
    /* Creamos un puntero intermedio */
    sym_value_type ptr = nodo;

    /* Pasamos la dirección del puntero */
    if (sym_add(nombre, &ptr) == SYMTAB_DUPLICATE) {
        fprintf(stderr, "Error: Variable %s ya declarada\n", nombre);
        /* No liberamos nodo aquí por simplicidad, aunque sería ideal */
    }
}

void sem_declarar_array(int tipo, char* nombre, int tamanyo) {
    /* Por ahora tratamos el array como una declaración normal en la tabla de símbolos.
       En la Fase 4 añadiremos el tamaño a la estructura si hace falta. */
    sem_declarar(tipo, nombre);
}

info_simbolo* sem_operar_binario(info_simbolo* a, info_simbolo* b, 
                                 char* op_int, char* op_float) {
    /* 1. Generar temporal */
    char* temporal = sem_generar_temporal();
    int tipo_result = T_ENTERO;
    char* instruccion = op_int;

    /* 2. Comprobación de tipos (Promoción a Real) */
    if (a->tipo == T_REAL || b->tipo == T_REAL) {
        tipo_result = T_REAL;
        instruccion = op_float;
        
        /* CASTING IMPLÍCITO */
        if (a->tipo == T_ENTERO) {
            char* temp_cast = sem_generar_temporal();
            sem_emitir("%s := I2F %s", temp_cast, a->nombre);
            a->nombre = temp_cast; 
            a->tipo = T_REAL;
        }
        if (b->tipo == T_ENTERO) {
            char* temp_cast = sem_generar_temporal();
            sem_emitir("%s := I2F %s", temp_cast, b->nombre);
            b->nombre = temp_cast;
            b->tipo = T_REAL;
        }
    }

    /* 3. Emitir instrucción binaria */
    sem_emitir("%s := %s %s %s", temporal, a->nombre, instruccion, b->nombre);

    /* 4. Devolver símbolo del temporal */
    return crear_nodo_info(temporal, tipo_result);
}

void sem_asignar(char* destino, info_simbolo* valor) {
    /* Asignación directa */
    sem_emitir("%s := %s", destino, valor->nombre);
}

void sem_imprimir_expresion(info_simbolo* s) {
    /* Generar PUT */
    sem_emitir("PARAM %s", s->nombre);
    if (s->tipo == T_ENTERO) {
        sem_emitir("CALL PUTI, 1");
    } else {
        sem_emitir("CALL PUTF, 1");
    }
}

void sem_cerrar_repeat(info_simbolo* contador, info_simbolo* tope, int etiqueta_inicio) {
    /* 1. Incrementamos el contador: contador := contador + 1 */
    /* Reutilizamos lógica: creamos un literal '1' para operar */
    /* Emitimos: $tXX := $tXX ADDI 1 */
    sem_emitir("%s := %s ADDI 1", contador->nombre, contador->nombre);
    
    /* 2. Emitimos el salto condicional: IF contador LTI tope GOTO etiqueta_inicio */
    /* El C3A define LTI (Less Than Integer) para comparar enteros */
    /* Formato: IF x oprel y GOTO L */
    sem_emitir("IF %s LTI %s GOTO %d", contador->nombre, tope->nombre, etiqueta_inicio);
    
}

info_simbolo* sem_acceder_array(char* nombre_array, info_simbolo* indice) {
    /* 1. Calcular el desplazamiento en bytes (índice * 4) */
    /* Nota: Asumimos int/float de 4 bytes siempre para esta práctica */
    char* t_offset = sem_generar_temporal();
    
    /* Si el índice es un literal numérico, podríamos optimizar, 
       pero lo tratamos genéricamente como variable/temporal */
    sem_emitir("%s := %s MULI 4", t_offset, indice->nombre);
    
    /* 2. Generar la instrucción de Consulta Desplazada: x := y[i] */
    char* t_resultado = sem_generar_temporal();
    
    /* C3A Sintaxis: $t_res := nombre_array[$t_offset] */
    sem_emitir("%s := %s[%s]", t_resultado, nombre_array, t_offset);
    
    /* 3. Devolver el temporal que contiene el valor leído */
    /* Asumimos tipo ENTERO por defecto o tendríamos que buscar el tipo del array en la tabla */
    return sem_crear_literal(t_resultado, T_ENTERO); 
}

void sem_asignar_array(char* nombre_array, info_simbolo* indice, info_simbolo* valor) {
    /* 1. Calcular el desplazamiento en bytes (índice * 4) */
    char* t_offset = sem_generar_temporal();
    sem_emitir("%s := %s MULI 4", t_offset, indice->nombre);
    
    /* 2. Generar la instrucción de Asignación Desplazada: x[i] := y */
    /* C3A Sintaxis: nombre_array[$t_offset] := valor */
    sem_emitir("%s[%s] := %s", nombre_array, t_offset, valor->nombre);
}

/* Stubs vacíos */
void sem_abrir_plantilla(char* n) {}
void sem_agregar_campo_a_plantilla(int t, char* i) {}
void sem_cerrar_plantilla() {}
void sem_declarar_instancia_actual(char* n) {}

