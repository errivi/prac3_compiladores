#ifndef SEMANTICA_H
#define SEMANTICA_H

#include "symtab.h"

// --- ESTRUCTURAS PARA BACKPATCHING ---

// Nodo de una lista de etiquetas pendientes de rellenar
typedef struct lista_nodos {
    int referencia; // Número de instrucción que tiene el hueco a rellenar
    struct lista_nodos *siguiente;
} lista_nodos;

// Estructura que devuelven las expresiones booleanas y sentencias
typedef struct {
    info_simbolo *simb;      // Para expresiones aritméticas (el resultado $t1)
    lista_nodos *truelist;   // Lista de saltos si es VERDADERO
    lista_nodos *falselist;  // Lista de saltos si es FALSO
    lista_nodos *nextlist;   // Lista de saltos al terminar el bloque
    int quad;                // Número de instrucción (para marcadores M)
} atributos;

// --- FUNCIONES DE BUFFER Y EMISIÓN ---

// Emite una instrucción al buffer y devuelve su número de línea
int sem_emitir(const char* fmt, ...);

// Imprime todo el buffer al fichero de salida (al final del main)
void sem_finalizar_salida(FILE* out);

// --- FUNCIONES DE LISTAS (BACKPATCHING) ---

// Crea una lista nueva con una sola referencia (número de instrucción)
lista_nodos* sem_makelist(int referencia);

// Fusiona dos listas en una sola
lista_nodos* sem_merge(lista_nodos* l1, lista_nodos* l2);

// Rellena las direcciones de los saltos de la lista con la etiqueta destino
void sem_backpatch(lista_nodos* lista, int etiqueta_destino);


// --- GESTIÓN DE VARIABLES Y OPERACIONES ---
char* sem_generar_temporal();
int sem_generar_etiqueta(); // Devuelve la siguiente instrucción libre

// Operaciones aritméticas (ahora devuelven atributos completos)
atributos sem_operar_binario(atributos A, atributos B, char* op_int, char* op_float);
atributos sem_crear_literal(char* valor, int tipo);
atributos sem_obtener_simbolo(char* nombre);
atributos sem_acceder_array(char* nombre_array, atributos indice);

// Sentencias
void sem_asignar(char* nombre_destino, atributos valor);
void sem_asignar_array(char* nombre_array, atributos indice, atributos valor);
void sem_imprimir_expresion(atributos s);
void sem_declarar(int tipo, char* nombre);
void sem_declarar_array(int tipo, char* nombre, int tamanyo);

// Operaciones booleanas
atributos sem_operar_relacional(atributos A, atributos B, char* op);

// Función específica para cerrar el bucle REPEAT
void sem_cerrar_repeat(info_simbolo* contador, info_simbolo* tope, int etiqueta_inicio);

// Gestión de SWITCH
void sem_push_switch(char* nombre_var); /* Entramos a un switch */
void sem_pop_switch();                  /* Salimos de un switch */
char* sem_get_switch_var();             /* ¿Qué variable estamos comparando? */

// Aux gestión bucle/switch
void sem_init_break_layer();
void sem_close_break_layer(int etiqueta_destino);
void sem_add_break();

// Loop unrolling
void sem_start_record();
char* sem_stop_record();
void sem_emitir_bloque(char* bloque);

// Utilidad
void yyerror(const char *s);

#endif