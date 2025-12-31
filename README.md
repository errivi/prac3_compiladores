# Práctica 3: Compilador a Código de Tres Direcciones (C3A)

**Asignatura:** Compiladores
**Autor:** Eric Riveiro
**Curso:** 2025-26

---

### 1. Descripción General
Este proyecto implementa un compilador completo capaz de analizar un lenguaje de programación imperativo estructurado y generar Código de Tres Direcciones (C3A).

El sistema utiliza **Flex** para el análisis léxico y **Bison** para el análisis sintáctico y semántico. A diferencia de un evaluador simple, este compilador implementa técnicas avanzadas de generación de código en una sola pasada, destacando el uso de **Backpatching** (parcheo hacia atrás) para resolver las direcciones de salto en estructuras de control complejas y la evaluación lógica en cortocircuito.

---

### 2. Características Implementadas

* **Generación Base de C3A:**
    * Traducción de expresiones aritméticas con precedencia correcta (`+`, `-`, `*`, `/`, `%`, `**`).
    * Gestión automática de tipos (`int`, `float`) e instrucciones específicas (`ADDI`/`ADDF`).
    * Generación de variables temporales secuenciales (`$t01`, `$t02`...).

* **Lógica Booleana y Cortocircuito:**
    * Implementación de operadores relacionales (`<`, `>`, `==`, etc.) y lógicos (`and`, `or`, `not`).
    * **Evaluación en Cortocircuito:** Las expresiones booleanas no generan valores numéricos, sino flujo de control. Si la primera parte de un `AND` es falsa, se salta el resto.

* **Estructuras de Control Condicional:**
    * `IF-THEN` y `IF-THEN-ELSE` con soporte completo de anidamiento.
    * **SWITCH:** Selección múltiple con lógica de cascada, soportando bloques `case`, `default` y anidamiento de switches.

* **Estructuras de Iteración (Bucles):**
    * **Indeterminados:** `WHILE` (evaluación inicial) y `DO-UNTIL` (evaluación final).
    * **Determinados:** `REPEAT` (repetición fija) y `FOR` (iterador acotado con incremento automático).

* **Gestión de Memoria (Arrays):**
    * Declaración y uso de vectores unidimensionales.
    * Cálculo de direcciones base + desplazamiento (offset) para instrucciones de acceso indexado.

* **Optimizaciones Avanzadas:**
    * **Loop Unrolling (Desenrollado de Bucles):** Para bucles `repeat` con un número de iteraciones literal pequeño (<= 5), el compilador elimina la estructura de control (`IF`/`GOTO`) y genera el código del cuerpo repetido secuencialmente, mejorando el rendimiento.
    * Implementado mediante un sistema de "Grabación de Buffer" en `semantica.c` que captura el código C3A antes de emitirlo.

* **Control de Flujo Explícito:**
    * **Instrucción `break`:** Permite salir prematuramente de cualquier bucle (`while`, `for`, `repeat`, `switch`).
    * Gestionado mediante una **Pila de Listas de Salida** (`break_list_stack`) que permite manejar correctamente los `break` dentro de bucles anidados.

---

### 3. Decisiones de Diseño

**A. Backpatching y Marcadores:**
Para evitar múltiples pasadas sobre el código fuente o el uso de etiquetas fijas precalculadas, se ha implementado un sistema de **Backpatching**.
* Se utilizan listas enlazadas de instrucciones incompletas (`truelist`, `falselist`, `nextlist`).
* Se introducen marcadores gramaticales no terminales (`M`, `N`) que capturan la posición actual (`quad`) o generan saltos incondicionales pendientes, permitiendo rellenar las direcciones de salto una vez que el parser alcanza el destino.

**B. Gestión del SWITCH (Pila de Contextos):**
El `SWITCH` presenta un desafío al permitir anidamiento (un switch dentro de otro).
* **Solución:** Se ha implementado una pila estática en C (`sem_push_switch` / `sem_pop_switch`) dentro de `semantica.c`.
* Esto permite guardar la variable que se está evaluando en el switch actual. Al entrar en un switch anidado, se apila la nueva variable, y al salir se desapila, garantizando que los `CASE` siempre comparen contra la variable correcta.
* La generación de código sigue un patrón de "Cascada IF-GOTO": Comprobar valor -> Ejecutar cuerpo -> Saltar al final.

**C. Estructura del Bucle FOR:**
El bucle `FOR` requiere ejecutar la inicialización y la condición *antes* del cuerpo, pero el incremento *después*.
* Se implementó una regla auxiliar `for_header` en la gramática. Esta regla genera la inicialización, la etiqueta de inicio y la condición de salida antes de procesar las sentencias, devolviendo la información necesaria (etiquetas y puntero al iterador) para generar el incremento y el salto de vuelta al cerrar el bucle.

---

### 4. Estructura del Proyecto

* `calculadora.l`: Analizador Léxico (Tokens, keywords, literales).
* `calculadora.y`: Analizador Sintáctico (Gramática, reglas de Backpatching y marcadores).
* `semantica.c/h`: Motor de generación. Contiene la lógica de emisión, las funciones de listas (makelist, merge, backpatch) y la pila del switch.
* `symtab.c/h`: Tabla de Símbolos (Gestión de variables y tipos).
* `Makefile`: Automatización de compilación y limpieza.

---

### 5. Instrucciones de Uso

**Compilación:**
```bash
make
```
**Ejecución Manual**
Para generar el C3A de un archivo de prueba específico:
```bash
./calculadora test_switch.txt
```
**Limpieza**
Para eliminar ejecutables y archivos temporales:
```bash
make clean
```