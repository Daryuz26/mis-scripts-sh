#!/bin/bash

# Script para extraer mensajes de error (glosas) desde logs remotos por SSH
# Autor: Anonimizado
# Versión: Limpia y preparada para uso general

# Configuración de rutas (usar rutas relativas o variables para mayor portabilidad)
BASE_DIR="./logs"
ERROR_LOG="$BASE_DIR/error.log"
EXEC_LOG="$BASE_DIR/execution.log"
RESULT_FILE="$BASE_DIR/result_glosas.csv"
INPUT_FILE="servers_list.txt"

USER="user_remote"
PASSWORD="password_placeholder"

# Función para registrar logs
log_message() {
    local MESSAGE=$1
    local LOG_TYPE=$2
    local TIMESTAMP
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    if [[ "$LOG_TYPE" == "error" ]]; then
        echo "$TIMESTAMP [ERROR] $MESSAGE" >> "$ERROR_LOG"
    else
        echo "$TIMESTAMP [INFO] $MESSAGE" >> "$EXEC_LOG"
    fi
}

# Verificar archivo de entrada
if [[ ! -f "$INPUT_FILE" ]]; then
    log_message "Archivo de entrada $INPUT_FILE no encontrado." "error"
    echo "Error: No se encuentra $INPUT_FILE"
    exit 1
fi

# Limpiar archivo CSV y agregar encabezado
mkdir -p "$BASE_DIR"
echo "Local,Nodo,IP,Glosa" > "$RESULT_FILE"
log_message "Archivo CSV $RESULT_FILE limpiado y encabezado agregado." "info"

# Leer todas las líneas del archivo servers_list.txt
mapfile -t LINES < "$INPUT_FILE"

for LINE in "${LINES[@]}"; do
    IFS=',' read -r LOCAL NODE IP <<< "$LINE"

    if [[ -n "$LOCAL" && -n "$NODE" && -n "$IP" ]]; then
        log_message "Procesando $LOCAL-$NODE ($IP)" "info"

        # Leer log remoto por SSH (asegúrate de tener sshpass instalado)
        LOG_CONTENT=$(sshpass -p "$PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$USER@$IP" \
          "cat /path/to/logs/biometry.log" 2>/dev/null)

        if [[ $? -ne 0 ]]; then
            log_message "Error de conexión SSH con $IP" "error"
            continue
        fi

        if [[ -n "$LOG_CONTENT" ]]; then
            # Extraer mensaje de glosa desde la excepción
            GLOSA=$(echo "$LOG_CONTENT" | grep -a "BiometryNotAuthorizedException:" | \
                    sed -nE 's/.*BiometryNotAuthorizedException: (.*)/\1/p' | head -n1)

            if [[ -n "$GLOSA" ]]; then
                log_message "Glosa extraída para $IP: $GLOSA" "info"
                echo "$LOCAL,$NODE,$IP,"$GLOSA"" >> "$RESULT_FILE"
            else
                log_message "No se encontró glosa para $IP" "info"
            fi
        else
            log_message "No se pudo leer el log en $IP" "error"
        fi
    else
        log_message "Línea malformada en $INPUT_FILE: '$LINE'" "error"
    fi
done

log_message "Proceso finalizado." "info"