# Práctica 2: Generación de Código de Tres Direcciones (C3A)

**Asignatura:** Compiladores (GEI)
**Autor:** Eric Riveiro
**Curso:** 2025-26

---

### 1. Descripción General
Este proyecto implementa el back-end de un compilador capaz de traducir un lenguaje de alto nivel (con soporte para arrays y estructuras de control iterativas) a Código de Tres Direcciones (C3A).

El compilador realiza el análisis léxico y sintáctico para posteriormente emitir instrucciones C3A numeradas, gestionando automáticamente la asignación de registros temporales ($tXX) y etiquetas de salto.

---

### 2. Características Implementadas

* **Generación de C3A:**
    * Traducción de expresiones aritméticas complejas a instrucciones simples (ADDI, MULF, etc.).
    * Gestión automática de casting implícito (promoción de `int` a `float`) insertando instrucciones `I2F`.
    * Generación de variables temporales secuenciales ($t01, $t02...).

* **Estructuras de Control (Repeat-Do-Done):**
    * Traducción de bucles `repeat` a patrones de salto condicional.
    * Gestión de etiquetas numéricas y contadores internos ocultos.
    * Lógica: Inicialización -> Cuerpo -> Incremento -> IF contador < N GOTO inicio.

* **Gestión de Memoria (Arrays/Taules):**
    * Soporte para arrays unidimensionales (`int a[10]`).
    * Cálculo explícito de direcciones de memoria (desplazamiento = índice * 4 bytes).
    * Generación de instrucciones de Consulta Desplazada (`$t := a[off]`) y Asignación Desplazada (`a[off] := $t`).

---

### 3. Decisiones de Diseño

**A. Arquitectura del Generador (`semantica.c`):**
Se ha sustituido el motor de evaluación de la práctica anterior por un motor de emisión.
* `sem_operar_binario`: Ya no calcula resultados. Genera un nuevo temporal, determina la instrucción correcta (ej: ADDI vs ADDF) basándose en los tipos de los operandos, y emite la línea de código.
* **Casting:** Se realiza una comprobación de tipos previa a la emisión. Si se detecta una operación mixta, se emite una instrucción de conversión `I2F` antes de la operación principal.

**B. Gestión de Bucles en Bison:**
Para permitir la generación de código del `repeat`, se ha introducido una regla auxiliar (`marcador_inicio_repeat`) en la gramática.
* Esta regla se ejecuta *antes* de procesar las sentencias del cuerpo.
* Su función es inicializar el contador del bucle ($tXX := 0) y capturar el número de línea (etiqueta) actual.
* Esto permite emitir el `GOTO` correcto al cerrar el bucle en la regla principal.

**C. Arrays y Desplazamientos:**
Se asume un tamaño de palabra de 4 bytes tanto para enteros como para reales.
* El acceso `a[i]` genera dos instrucciones C3A: una multiplicación (`MULI 4`) para obtener el offset y el acceso indexado.

---

### 4. Estructura del Proyecto

* `calculadora.l`: Analizador Léxico (Reconoce tokens repeat, arrays, opcions...).
* `calculadora.y`: Analizador Sintáctico (Define la gramática y coordina la generación).
* `semantica.c/h`: Motor de generación de C3A. Gestiona temporales, etiquetas y emisión.
* `symtab.c/h`: Tabla de Símbolos (Almacena declaraciones).
* `Makefile`: Script de compilación y testing.

---

### 5. Instrucciones de Uso

**Compilación:**
```bash
make
```
**Ejecución de Tests Automáticos:**
El proyecto incluye una batería de pruebas que verifica cada fase del desarrollo.
```bash
make test
```
Esto generará dos carpetas:
* `resultados_pruebas_test/`: Contiene los ficheros .out con el código C3A generado.
* `logs_pruebas_test/`: Contiene los logs de depuración interna del parser.

**Ejecución Manual:**
```bash
./calculadora pruebas_test/prueba_fase4.txt
```
**Limpieza:**
```bash
make clean
```
**Preparación de la carpeta `pruebas_test`**
Asegúrate de tener la carpeta creada y mete ahí tus archivos .txt:
```bash
mkdir -p pruebas_test
# Mueve o crea aquí los archivos:
# prueba_fase1.txt
# prueba_fase2.txt
# prueba_fase3.txt
# prueba_fase4.txt
