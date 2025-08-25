#!/bin/bash
# Script para actualizar propiedades y validar modos de pago en servidores remotos
# Versión: Generalizada, sin datos sensibles expuestos

# Variables auxiliares
auxOK=1
auxNO=0
fecha_ayer=$(date +%d-%m-%Y --date='-1 day')

# Función para log
log () {
    echo "$1"
    echo "$1" >> "$(basename "$0" .sh).log"
}

# Función para registrar si fue OK o ERROR
valido () {
    if [ $1 -eq 0 ]; then
        echo "$nroLocal,$nodo,$ipLocal" >> OK
    else
        echo "$nroLocal,$nodo,$ipLocal" >> ERROR
    fi
}

# Librerías JDBC
jisql_classpath="${JISQL_CLASSPATH:-lib/jisql-2.0.11.jar:lib/jopt-simple-3.2.jar:lib/ojdbc-14.jar}"

# Variables sensibles tomadas de entorno
oracle_host="${ORACLE_HOST:?Debe exportar ORACLE_HOST}"
oracle_user="${ORACLE_USER:?Debe exportar ORACLE_USER}"
oracle_password="${ORACLE_PASSWORD:?Debe exportar ORACLE_PASSWORD}"
oracle_service="${ORACLE_SERVICE:?Debe exportar ORACLE_SERVICE}"
mysql_pass="${MYSQL_PASS:?Debe exportar MYSQL_PASS}"
mysql_db="${MYSQL_DB:-geopos2cruzverde}"

# Función para ejecutar consulta SQL Oracle usando java Jisql
run_query_oracle() {
    local query=$1
    local db_ip=$2
    local db_user=$3
    local db_sn=$4
    local db_password=$5
    local db_driver=oracle.jdbc.driver.OracleDriver
    local db_url="jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$db_ip)(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=$db_sn)))"
    if [ -z "$query" ]; then
        echo "ERROR: no se envió la query"
        return 1
    fi
    java -Xmx1G -XX:MaxPermSize=1G -XX:PermSize=128m -classpath "$jisql_classpath" com.xigole.util.sql.Jisql \
         -user "$db_user" -password "$db_password" -driver "$db_driver" -cstring "$db_url" -c \; -query "$query" > aux.txt
}

log "COMIENZO EL PROCESO"
log "Versión generalizada del script"

# Verificar existencia de clave SSH
KEY="$HOME/.ssh/id_dsa.pub"
if [ ! -f "$KEY" ]; then
    echo "Clave pública SSH no encontrada en $KEY"
    echo "Por favor, crea una con 'ssh-keygen -t dsa' y sin contraseña para acceso sin password"
    exit 1
fi

echo "Ingrese el número de local:"
read nroLocal

if ! [[ "$nroLocal" =~ ^[0-9]+$ ]]; then
    echo "El número de local debe ser un valor numérico."
    exit 1
fi

if [ -z "$nroLocal" ]; then
    echo "El número de local no puede estar vacío."
    exit 1
fi

log "Conectando a Oracle para obtener nodos de local $nroLocal..."
query="SELECT localid, node, IPADDRESS FROM nodes WHERE localid=$nroLocal;"

run_query_oracle "$query" "$oracle_host" "$oracle_user" "$oracle_service" "$oracle_password"

if [ ! -s aux.txt ]; then
    log "No se encontraron resultados para local $nroLocal en la base de datos Oracle."
    exit 1
fi

tail -n +2 aux.txt | while read -r line; do
    line_clean=$(echo "$line" | sed 's/|//g' | sed 's/^[ \t]//;s/[ \t]$//')
    localid=$(echo "$line_clean" | awk '{print $1}')
    nodo=$(echo "$line_clean" | awk '{print $2}')
    ipLocal=$(echo "$line_clean" | awk '{print $3}')

    if [[ -z "$nodo" || -z "$ipLocal" || -z "$localid" ]]; then
        log "Error: Datos incompletos para nodo=$nodo, localid=$localid, ipLocal=$ipLocal. Ignorando..."
        continue
    fi

    ping -c 1 -W 1 "$ipLocal" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "IP $ipLocal no responde a ping, pasando al siguiente servidor."
        continue
    fi

    current_value=$(mysql -p"$mysql_pass" --connect-timeout=10 --skip-column-names -h"$ipLocal" -e \
        "SELECT value FROM $mysql_db.nodeproperties WHERE LOCALID=$localid AND NAME='WIRELESS_TBK';")

    mysql -p"$mysql_pass" --connect-timeout=10 --skip-column-names -h"$ipLocal" $mysql_db -e \
        "UPDATE nodeproperties SET value = 'true' WHERE LOCALID=$localid AND NAME='WIRELESS_TBK';"
    valido $?

    new_value=$(mysql -p"$mysql_pass" --connect-timeout=10 --skip-column-names -h"$ipLocal" -e \
        "SELECT value FROM $mysql_db.nodeproperties WHERE LOCALID=$localid AND NAME='WIRELESS_TBK';")

    echo "+------------------------------------------------+"
    echo "| Nodo: $nodo                                   |"
    echo "| IP: $ipLocal                                  |"
    echo "| WIRELESS_TBK Antes: $current_value            |"
    echo "| WIRELESS_TBK Después: $new_value               |"

    for pmid in 402 403; do
        eliminated_before=$(mysql -p"$mysql_pass" --connect-timeout=10 --skip-column-names -h"$ipLocal" -e \
            "SELECT eliminated FROM $mysql_db.paymentmodes WHERE id=$pmid;")

        if [ "$eliminated_before" = true ]; then
            mysql -p"$mysql_pass" --connect-timeout=10 --skip-column-names -h"$ipLocal" $mysql_db -e \
                "UPDATE paymentmodes SET eliminated=false WHERE id=$pmid;"
        fi

        eliminated_after=$(mysql -p"$mysql_pass" --connect-timeout=10 --skip-column-names -h"$ipLocal" -e \
            "SELECT eliminated FROM $mysql_db.paymentmodes WHERE id=$pmid;")

        printf "| Eliminated PM%s: %s → %s\n" "$pmid" "$eliminated_before" "$eliminated_after"
    done

    echo "+------------------------------------------------+"

    echo "$nodo,$localid,$new_value" >> tbki.csv

done

log "Ejecutando UPDATE en la base central para LOCALID=$nroLocal..."
query_update="UPDATE $mysql_db.nodeproperties SET VALUE='true' WHERE NODE='99' AND LOCALID='$nroLocal' AND NAME='WIRELESS_TBK';"

java -Xmx1G -XX:MaxPermSize=1G -XX:PermSize=128m -classpath "$jisql_classpath" com.xigole.util.sql.Jisql \
     -user "$oracle_user" -password "$oracle_password" -driver oracle.jdbc.driver.OracleDriver \
     -cstring "jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$oracle_host)(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=$oracle_service)))" \
     -c \; -query "$query_update"

if [ $? -eq 0 ]; then
    log "UPDATE exitoso para LOCALID=$nroLocal en la base Oracle central."
else
    log "Error al realizar UPDATE en LOCALID=$nroLocal en la base Oracle central."
fi

rm -f aux.txt
log "Archivo aux.txt eliminado."
log "PROCESO FINALIZADO"