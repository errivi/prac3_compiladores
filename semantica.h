#ifndef SEMANTICA_H
#define SEMANTICA_H

#include "symtab.h"

/* --- HERRAMIENTAS DE GENERACIÓN C3A --- */
/* Genera un nombre de variable temporal nuevo: "$t1", "$t2"... */
char* sem_generar_temporal();

/* Genera una etiqueta/número de línea para saltos: 10, 11... */
int sem_generar_etiqueta();

/* Emite una instrucción C3A numerada al output */
void sem_emitir(const char* fmt, ...);

/* --- GESTIÓN DE SIMBOLOS Y LITERALES --- */
/* Crea un símbolo a partir de un literal (ej: "10" o "3.5") */
info_simbolo* sem_crear_literal(char* valor, int tipo);

/* Busca una variable y devuelve su info (o crea un dummy si falla) */
info_simbolo* sem_obtener_simbolo(char* nombre);

/* --- OPERACIONES --- */
/* Genera código para operación binaria (Suma, Resta, Mult, Div) */
/* Devuelve el símbolo temporal donde se guardó el resultado */
info_simbolo* sem_operar_binario(info_simbolo* a, info_simbolo* b, 
                                 char* op_int, char* op_float);

/* Declaración de variables (solo tabla de símbolos) */
void sem_declarar(int tipo, char* nombre);

/* Declaración de arrays: int a[10] */
void sem_declarar_array(int tipo, char* nombre, int tamanyo);

/* Asignación simple: x := 5 */
void sem_asignar(char* nombre_destino, info_simbolo* valor);

/* Impresión (ahora genera PUT) */
void sem_imprimir_expresion(info_simbolo* s);

/* --- UTILIDADES --- */
void yyerror(const char *s);
const char* tipo_a_cadena(tipo_variable tipo);

/* --- STUBS (Para mantener compatibilidad con Práctica 1 si fuera necesario) --- */
void sem_abrir_plantilla(char* nombre);
void sem_agregar_campo_a_plantilla(int tipo, char* id);
void sem_cerrar_plantilla();
void sem_declarar_instancia_actual(char* nombre_instancia);

/* Genera el código final del bucle repeat: Incr. contador + IF GOTO */
void sem_cerrar_repeat(info_simbolo* contador, info_simbolo* tope, int etiqueta_inicio);


/* Genera código para leer de un array: devuelve el temporal con el valor */
info_simbolo* sem_acceder_array(char* nombre_array, info_simbolo* indice);

/* Genera código para escribir en un array */
void sem_asignar_array(char* nombre_array, info_simbolo* indice, info_simbolo* valor);

#endif