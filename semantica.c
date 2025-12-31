#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "semantica.h"

#define MAX_INSTRUCCIONES 10000
#define TAM_BUFFER 256

/* Buffer de instrucciones en memoria */
static char* instrucciones[MAX_INSTRUCCIONES];
static int sig_instruccion = 1; /* Empieza en 1 */
static int contador_temporales = 1;

// variables pila para switch (hasta 10 anidados)
static char* switch_stack[10];
static int switch_top = 0; // índice tope de la pila

// variables pila para break (hasta 20 anidados)
static lista_nodos* break_list_stack[20];
static int break_list_top = 0;   // índice tope de la pila */

// variabes para loop unrolling
static int recording = 0;
static char code_buffer[4096];     // buffer para guardar cuerpo bucle limitado a 4KB

/* --- GESTIÓN DEL BUFFER DE CÓDIGO --- */

int sem_generar_etiqueta() {
    return sig_instruccion;
}
int sem_emitir(const char* fmt, ...) {
    va_list args;
    
    /* modo para loop unrolling (guardando cuerpo bucle) */
    if (recording) {
        char temp[1024]; // Buffer temporal local
        
        va_start(args, fmt);
        vsnprintf(temp, 1024, fmt, args);
        va_end(args);
        
        /* Concatenamos al buffer global */
        if (strlen(code_buffer) + strlen(temp) + 2 < 4096) {
            strcat(code_buffer, temp);
            strcat(code_buffer, "\n");
        } else {
            fprintf(stderr, "Error: Cuerpo del bucle demasiado grande para unrolling.\n");
        }
        
        return 0; // No cuenta como instrucción emitida
    }

    /* modo normal*/
    if (sig_instruccion >= MAX_INSTRUCCIONES) {
        fprintf(stderr, "Error fatal: Programa demasiado grande (max %d lineas)\n", MAX_INSTRUCCIONES);
        exit(1);
    }

    char* buffer = malloc(TAM_BUFFER); 
    
    va_start(args, fmt);
    vsnprintf(buffer, TAM_BUFFER, fmt, args);
    va_end(args);

    instrucciones[sig_instruccion] = buffer;
    return sig_instruccion++; 
}

void sem_finalizar_salida(FILE* out) {
    if (!out) out = stdout;
    for (int i = 1; i < sig_instruccion; i++) {
        if (instrucciones[i]) {
            fprintf(out, "%d: %s\n", i, instrucciones[i]);
            free(instrucciones[i]); // Limpieza
        }
    }
}

/* --- OPERACIONES DE LISTAS (BACKPATCHING) --- */

lista_nodos* sem_makelist(int referencia) {
    lista_nodos* p = malloc(sizeof(lista_nodos));
    p->referencia = referencia;
    p->siguiente = NULL;
    return p;
}

lista_nodos* sem_merge(lista_nodos* l1, lista_nodos* l2) {
    if (!l1) return l2;
    if (!l2) return l1;
    
    lista_nodos* p = l1;
    while (p->siguiente != NULL) {
        p = p->siguiente;
    }
    p->siguiente = l2;
    return l1;
}

void sem_backpatch(lista_nodos* lista, int etiqueta_destino) {
    lista_nodos* p = lista;
    while (p != NULL) {
        int ref = p->referencia;
        if (ref < sig_instruccion && instrucciones[ref] != NULL) {
            // Reconstruimos la cadena añadiendo el número de etiqueta
            // Asumimos que la instrucción guardada era incompleta (ej: "IF ... GOTO")
            char nuevo_buffer[TAM_BUFFER];
            snprintf(nuevo_buffer, TAM_BUFFER, "%s %d", instrucciones[ref], etiqueta_destino);
            
            free(instrucciones[ref]);
            instrucciones[ref] = strdup(nuevo_buffer);
        }
        p = p->siguiente;
    }
}

/* --- AUXILIARES Y GESTIÓN DE SÍMBOLOS --- */

char* sem_generar_temporal() {
    char* temp = malloc(20);
    sprintf(temp, "$t%02d", contador_temporales++);
    return temp;
}

// Helper interno para devolver struct atributos limpio
atributos crear_atribs(info_simbolo* s) {
    atributos a;
    a.simb = s;
    a.truelist = NULL;
    a.falselist = NULL;
    a.nextlist = NULL;
    a.quad = 0;
    return a;
}

atributos sem_crear_literal(char* valor, int tipo) {
    info_simbolo* s = malloc(sizeof(info_simbolo));
    s->nombre = strdup(valor);
    s->tipo = tipo;
    s->u.valor_int = 0; 
    return crear_atribs(s);
}

/* Función para crear un temporal "vacío" (usada en bucles para contadores) */
atributos sem_crear_temporal(int tipo) {
    /* 1. Obtenemos un nombre nuevo ($tXX) usando función existente */
    char* nombre = sem_generar_temporal();
    
    /* 2. Empaquetamos en la estructura 'atributos' usando función existente */
    /* Aunque se llame 'literal', sirve para crear la estructura del símbolo */
    return sem_crear_literal(nombre, tipo);
}

atributos sem_obtener_simbolo(char* nombre) {
    sym_value_type info;
    if (sym_lookup(nombre, &info) == SYMTAB_NOT_FOUND) {
        char err[100];
        sprintf(err, "Variable no declarada: %s", nombre);
        yyerror(err);
        return sem_crear_literal("err", T_ERROR);
    }
    // Creamos copia ligera
    info_simbolo* copia = malloc(sizeof(info_simbolo));
    copia->nombre = info->nombre;
    copia->tipo = info->tipo;
    return crear_atribs(copia);
}

void sem_declarar(int tipo, char* nombre) {
    info_simbolo* nodo = malloc(sizeof(info_simbolo));
    nodo->tipo = tipo;
    nodo->nombre = strdup(nombre);
    nodo->u.valor_int = 0;
    sym_value_type ptr = nodo;
    
    if (sym_add(nombre, &ptr) == SYMTAB_DUPLICATE) {
        fprintf(stderr, "Error: Variable %s ya declarada\n", nombre);
    }
}

void sem_declarar_array(int tipo, char* nombre, int tamanyo) {
    sem_declarar(tipo, nombre); // Simplificado
}

/* --- OPERACIONES --- */

atributos sem_operar_binario(atributos A, atributos B, char* op_int, char* op_float) {
    char* temporal = sem_generar_temporal();
    int tipo_result = T_ENTERO;
    char* instruccion = op_int;

    // Casting implícito básico
    if (A.simb->tipo == T_REAL || B.simb->tipo == T_REAL) {
        tipo_result = T_REAL;
        instruccion = op_float;
        
        if (A.simb->tipo == T_ENTERO) {
            char* temp_cast = sem_generar_temporal();
            sem_emitir("%s := I2F %s", temp_cast, A.simb->nombre);
            A.simb->nombre = temp_cast;
        }
        if (B.simb->tipo == T_ENTERO) {
            char* temp_cast = sem_generar_temporal();
            sem_emitir("%s := I2F %s", temp_cast, B.simb->nombre);
            B.simb->nombre = temp_cast;
        }
    }

    sem_emitir("%s := %s %s %s", temporal, A.simb->nombre, instruccion, B.simb->nombre);
    return sem_crear_literal(temporal, tipo_result);
}

void sem_asignar(char* destino, atributos valor) {
    sem_emitir("%s := %s", destino, valor.simb->nombre);
}

void sem_asignar_array(char* nombre_array, atributos indice, atributos valor) {
    char* t_offset = sem_generar_temporal();
    sem_emitir("%s := %s MULI 4", t_offset, indice.simb->nombre);
    sem_emitir("%s[%s] := %s", nombre_array, t_offset, valor.simb->nombre);
}

atributos sem_acceder_array(char* nombre_array, atributos indice) {
    char* t_offset = sem_generar_temporal();
    sem_emitir("%s := %s MULI 4", t_offset, indice.simb->nombre);
    char* t_res = sem_generar_temporal();
    sem_emitir("%s := %s[%s]", t_res, nombre_array, t_offset);
    return sem_crear_literal(t_res, T_ENTERO);
}

void sem_imprimir_expresion(atributos s) {
    sem_emitir("PARAM %s", s.simb->nombre);
    if (s.simb->tipo == T_REAL) sem_emitir("CALL PUTF, 1");
    else sem_emitir("CALL PUTI, 1");
}

void sem_cerrar_repeat(info_simbolo* contador, info_simbolo* tope, int etiqueta_inicio) {
    // Reimplementación usando el nuevo sem_emitir
    sem_emitir("%s := %s ADDI 1", contador->nombre, contador->nombre);
    sem_emitir("IF %s LTI %s GOTO %d", contador->nombre, tope->nombre, etiqueta_inicio);
}

/* --- LÓGICA BOOLEANA --- */

atributos sem_operar_relacional(atributos A, atributos B, char* op) {
    /* 1. Comprobar tipos y castear si es necesario (igual que en binario) */
    char* sufijo = "I"; // Por defecto Entero
    if (A.simb->tipo == T_REAL || B.simb->tipo == T_REAL) {
        sufijo = "F";   // Si alguno es real, usamos Float
        // (Aquí irían los castings I2F si quieres ser purista, por ahora asumimos compatibilidad)
    }

    /* 2. Construir el operador completo (ej: "LTI" o "LTF") */
    char op_completo[10];
    sprintf(op_completo, "%s%s", op, sufijo);

    /* 3. Generar el salto condicional VERDADERO incompleto */
    /* "IF a LT b GOTO [hueco]" */
    int instr_true = sem_emitir("IF %s %s %s GOTO", A.simb->nombre, op_completo, B.simb->nombre);
    
    /* 4. Generar el salto FALSO incompleto (un GOTO incondicional justo después) */
    /* Si no saltó en el IF, caerá aquí. "GOTO [hueco]" */
    int instr_false = sem_emitir("GOTO");

    /* 5. Crear las listas de backpatching */
    atributos res;
    res.simb = NULL; // Una exp booleana no tiene valor "$t", tiene flujo
    
    /* La truelist contiene la instrucción del IF (que saltará si es verdad) */
    res.truelist = sem_makelist(instr_true);
    
    /* La falselist contiene la instrucción del GOTO (que saltará si es mentira) */
    res.falselist = sem_makelist(instr_false);
    
    res.nextlist = NULL;
    return res;
}

/* --- GESTIÓN DE SWITCH --- */

void sem_push_switch(char* nombre_var) {
    if (switch_top < 10) {
        switch_stack[switch_top++] = strdup(nombre_var);
    }
}

void sem_pop_switch() {
    if (switch_top > 0) {
        switch_top--;
    }
}

char* sem_get_switch_var() {
    if (switch_top > 0) return switch_stack[switch_top - 1];
    return "err";
}

/* --- PILA DE LISTAS DE BREAK --- */

void sem_init_break_layer() {
    /* Iniciamos una nueva capa (nuevo bucle) */
    if (break_list_top < 20) {
        break_list_stack[break_list_top++] = NULL; // Lista vacía
    }
}

void sem_close_break_layer(int etiqueta_destino) {
    /* Cerramos capa y rellenamos todos los breaks pendientes de este nivel */
    if (break_list_top > 0) {
        break_list_top--;
        sem_backpatch(break_list_stack[break_list_top], etiqueta_destino);
    }
}

void sem_add_break() {
    /* Añadimos un salto pendiente a la capa actual */
    if (break_list_top > 0) {
        int salto = sem_emitir("GOTO"); // Salto hueco
        // Añadir a la lista del tope de la pila
        break_list_stack[break_list_top - 1] = 
            sem_merge(break_list_stack[break_list_top - 1], sem_makelist(salto));
    }
}

/* --- LOOP UNROLLING --- */

void sem_start_record() {
    recording = 1;
    code_buffer[0] = '\0'; // Limpiar buffer
}

char* sem_stop_record() {
    recording = 0;
    return strdup(code_buffer); // Devolver copia del buffer
}

/* Función auxiliar para imprimir un bloque de texto línea a línea */
void sem_emitir_bloque(char* bloque) {
    if (!bloque) return;
    char* copia = strdup(bloque); // Copia para no romper el original con strtok
    char* linea = strtok(copia, "\n");
    while (linea != NULL) {
        /* Usamos sem_emitir para que ponga el número de línea correcto */
        sem_emitir("%s", linea);
        linea = strtok(NULL, "\n");
    }
    free(copia);
}