#!/bin/bash

# Parámetros comunes (usar variables de entorno para datos sensibles)
DB_USER="${DB_USER:?Debe exportar DB_USER}"
DB_PASS="${DB_PASS:?Debe exportar DB_PASS}"
DB_NAME="${DB_NAME:-geopos2cruzverde}"
SERVIDORES="${SERVIDORES:-servidores.txt}"
SALIDA="${SALIDA:-resultado_cierre.csv}"
SQL="SELECT local, processDate, countableDate, event FROM localprocess ORDER BY id DESC LIMIT 1;"
FECHA_HOY=$(date +%F)

# Verificar que mysql está instalado
command -v mysql >/dev/null 2>&1 || { echo >&2 "El cliente mysql no está instalado. Abortando."; exit 1; }

# Verificar que el archivo de servidores existe
if [ ! -f "$SERVIDORES" ]; then
    echo "Archivo de servidores '$SERVIDORES' no encontrado."
    exit 1
fi

# Cabecera CSV para Excel
echo "localid,nodo,ip,local,processDate,countableDate,event,estado" > "$SALIDA"

# Leer servidores (omitimos cabecera)
tail -n +2 "$SERVIDORES" | while IFS=',' read -r localid nodo ip; do
    echo "Consultando $ip (LocalID $localid)..."

    # Ejecutar consulta en el servidor remoto MySQL y capturar resultado
    RESULT=$(mysql -u"$DB_USER" -p"$DB_PASS" -h "$ip" -D "$DB_NAME" -N -e "$SQL" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$RESULT" ]; then
        # Extraer resultados de la consulta
        IFS=$'\t' read -r local processDate countableDate event <<< "$RESULT"

        # Extraer solo fecha sin hora
        countableDate_only=$(echo "$countableDate" | cut -d' ' -f1)
        processDate_only=$(echo "$processDate" | cut -d' ' -f1)

        # Verificar si countableDate es hoy
        if [ "$countableDate_only" == "$FECHA_HOY" ]; then
            estado="OK"
        else
            estado="NO_CIERRE_HOY"
        fi

        # Verificar evento "end_day_process"
        if [ "$event" == "end_day_process" ]; then
            estado="$estado,LOCAL_CERRADO"
        fi

        # Guardar resultado en CSV
echo "$localid,$nodo,$ip,$local,$processDate,$countableDate,$event,$estado" >> "$SALIDA"
    else
        echo "$localid,$nodo,$ip,ERROR,ERROR,ERROR,ERROR,ERROR" >> "$SALIDA"
    fi
done

echo "✅ Proceso completado. Resultado en: $SALIDA"