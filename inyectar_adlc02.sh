#!/bin/bash

# Automatiza la inyección de XML a un endpoint SOAP para locales
# Autor: Anonimizado
# Versión: 1.2
# Uso: Proceso de carga de configuraciones ADLC02 por local

source ./utils.sh  # Asegúrate de tener funciones auxiliares en este archivo

CSV_FILE="./output/respuestas_soap.csv"
INPUT_FILE="./data/xml_a_inyectar.txt"

echo "Local,Mensaje,correlationId,responseCode,isAuthorized,rxDate" > "$CSV_FILE"

log "INICIO DEL PROCESO"
log "Versión 1.2 - Inyección ADLC02 desde archivo nroLocal,XML"

llaveSUSE  # Función externa para gestionar credenciales o configuraciones

# Preguntar tipo de local
while true; do
    read -p "¿Es FCV o MCO? (Escribe FCV o MCO): " tipo_local
    tipo_local=$(echo "$tipo_local" | tr '[:upper:]' '[:lower:]')

    if [[ "$tipo_local" == "fcv" ]]; then
        company="86"
        chain="10"
        break
    elif [[ "$tipo_local" == "mco" ]]; then
        company="98"
        chain="40"
        break
    else
        echo "Valor incorrecto. Debes ingresar 'FCV' o 'MCO'."
    fi
done

tipo_local=$(echo "$tipo_local" | tr '[:lower:]' '[:upper:]')

# Leer archivo con datos
while IFS=',' read -r nroLocal adlc02_raw; do
    [[ -z "$nroLocal" || -z "$adlc02_raw" ]] && continue

    log "Procesando local $nroLocal"

    # Crear XML SOAP
    soap_envelope="<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:ws=\"http://ws.example.com/\">\n  <soapenv:Header/>\n  <soapenv:Body>\n    <ws:process_ADLC02>\n      $adlc02_raw\n      <posConfig>\n        <company>"+company+"</company>\n        <chain>"+chain+"</chain>\n        <merchantCode>"+nroLocal+"</merchantCode>\n        <posNumber>0</posNumber>\n        <machineNumber>0</machineNumber>\n        <user>"+tipo_local+"</user>\n      </posConfig>\n    </ws:process_ADLC02>\n  </soapenv:Body>\n</soapenv:Envelope>"

    # ATENCIÓN: Reemplaza <SOAP_SERVER_IP> por la IP/hostname real del endpoint SOAP
    SOAP_URL="http://<SOAP_SERVER_IP>/servicio/ADL?wsdl"
    SOAP_HEADER="Content-Type: text/xml;charset=UTF-8"
    SOAP_ACTION="SOAPAction: 'process_ADLC02'"

    response=$(curl -s -X POST "$SOAP_URL" -H "$SOAP_HEADER" -H "$SOAP_ACTION" -d "$soap_envelope")

    if echo "$response" | grep -q "<responseCode>611</responseCode>"; then
        mensaje="611 transacción inyectada con éxito"
        correlationId=$(echo "$response" | grep -oPm1 "(?<=<correlationId>)[^<]+")
        responseCode=$(echo "$response" | grep -oPm1 "(?<=<responseCode>)[^<]+")
        isAuthorized=$(echo "$response" | grep -oPm1 "(?<=<isAuthorized>)[^<]+")
        rxDate=$(echo "$response" | grep -oPm1 "(?<=<rxDate>)[^<]+")
    else
        mensaje="Error: no se inyectó"
        correlationId=""
        responseCode=""
        isAuthorized=""
        rxDate=""
    fi

    echo "$nroLocal,\"$mensaje\",\"$correlationId\",\"$responseCode\",\"$isAuthorized\",\"$rxDate\"" >> "$CSV_FILE"
    sleep 1

done < "$INPUT_FILE"

log "Proceso finalizado"