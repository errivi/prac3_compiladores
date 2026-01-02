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

# --- Lista de Tests ---
# Añade aquí los nombres de los ficheros .txt que quieras probar
TEST_FILES = test_aritmetica_buclesSimples.txt \
             test_bool.txt \
             test_break.txt \
             test_bucles.txt \
             test_for.txt \
             test_if.txt \
             test_switch.txt \
             test_unroll.txt \
             test_completo.txt \
             test_estres.txt

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

# --- Limpieza y Tests Automáticos ---

clean:
	rm -f $(TARGET) $(FLEX_C) $(BISON_C) $(BISON_H) *.o *.log *.out
	rm -rf $(RESULTS_DIR) $(LOGS_DIR)

test: $(TARGET)
	@echo "========================================"
	@echo "   INICIANDO BATERIA DE TESTS (AUTO)    "
	@echo "========================================"
	@mkdir -p $(RESULTS_DIR)
	@mkdir -p $(LOGS_DIR)
	@count=1; \
	total=$(words $(TEST_FILES)); \
	for file in $(TEST_FILES); do \
		echo "[$${count}/$${total}] Ejecutando $$file ..."; \
		base=$${file%.*}; \
		./$(TARGET) $(TEST_DIR)/$$file > $(RESULTS_DIR)/$${base}.out 2>&1; \
		if [ -f calculadora.log ]; then \
			mv calculadora.log $(LOGS_DIR)/$${base}.log; \
		else \
			echo "   (Nota: No se generó log para $$file)"; \
		fi; \
		count=$$((count + 1)); \
	done
	@echo "========================================"
	@echo " TESTS FINALIZADOS "
	@echo " -> Resultados C3A en: $(RESULTS_DIR)/"
	@echo " -> Logs de depuracion en: $(LOGS_DIR)/"
	@echo "========================================"

.PHONY: all clean test