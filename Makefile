# --- Variables de configuración ---
TARGET = calculadora
TEST_DIR = pruebas_test
RESULTS_DIR = resultados_pruebas_test
LOGS_DIR = logs_pruebas_test

# Ficheros fuente
FLEX_SRC = calculadora.l
BISON_SRC = calculadora.y
SYM_SRC = symtab.c
SEM_SRC = semantica.c

# Objetos
SYM_OBJ = symtab.o
SEM_OBJ = semantica.o
FLEX_C = lex.yy.c
BISON_C = calculadora.tab.c
BISON_H = calculadora.tab.h

# Compilador y flags
CC = gcc
CFLAGS = -Wall -g
LIBS = -lm

# --- Reglas Principales ---

all: $(TARGET)

$(TARGET): $(BISON_C) $(FLEX_C) $(SYM_OBJ) $(SEM_OBJ)
	$(CC) $(CFLAGS) -o $(TARGET) $(BISON_C) $(FLEX_C) $(SYM_OBJ) $(SEM_OBJ) $(LIBS)

$(BISON_C): $(BISON_SRC)
	bison -d $(BISON_SRC)

$(FLEX_C): $(FLEX_SRC) $(BISON_H)
	flex $(FLEX_SRC)

$(BISON_H): $(BISON_C)

$(SYM_OBJ): $(SYM_SRC)
	$(CC) $(CFLAGS) -c $(SYM_SRC)

$(SEM_OBJ): $(SEM_SRC)
	$(CC) $(CFLAGS) -c $(SEM_SRC)

# --- Limpieza y Tests ---

clean:
	rm -f $(TARGET) $(FLEX_C) $(BISON_C) $(BISON_H) *.o *.log *.out
	rm -rf $(RESULTS_DIR) $(LOGS_DIR)

test: $(TARGET)
	@echo "--- Iniciando Bateria de Tests ---"
	@mkdir -p $(RESULTS_DIR)
	@mkdir -p $(LOGS_DIR)
	
	@echo "[1/5] Test Aritmetica Basica..."
	-./$(TARGET) $(TEST_DIR)/test_aritmetica.txt > $(RESULTS_DIR)/test_aritmetica.out 2>&1
	@if [ -f calculadora.log ]; then mv calculadora.log $(LOGS_DIR)/test_aritmetica.log; fi
	
	@echo "[2/5] Test Estructura Repeat..."
	-./$(TARGET) $(TEST_DIR)/test_repeat.txt > $(RESULTS_DIR)/test_repeat.out 2>&1
	@if [ -f calculadora.log ]; then mv calculadora.log $(LOGS_DIR)/test_repeat.log; fi
	
	@echo "[3/5] Test Arrays (Taules)..."
	-./$(TARGET) $(TEST_DIR)/test_arrays.txt > $(RESULTS_DIR)/test_arrays.out 2>&1
	@if [ -f calculadora.log ]; then mv calculadora.log $(LOGS_DIR)/test_arrays.log; fi

	@echo "[4/5] Test Integrado Completo..."
	-./$(TARGET) $(TEST_DIR)/test_completo.txt > $(RESULTS_DIR)/test_completo.out 2>&1
	@if [ -f calculadora.log ]; then mv calculadora.log $(LOGS_DIR)/test_completo.log; fi

	@echo "[5/5] Test de Estres..."
	-./$(TARGET) $(TEST_DIR)/test_estres.txt > $(RESULTS_DIR)/test_estres.out 2>&1
	@if [ -f calculadora.log ]; then mv calculadora.log $(LOGS_DIR)/test_estres.log; fi

	@echo "--- Tests finalizados. Resultados en $(RESULTS_DIR)/ ---"

.PHONY: all clean test