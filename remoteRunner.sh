#!/usr/bin/env bash

: '
CÓDIGOS DE ERROR

1: Este código se lanzará cuando se ejecute el script con sudo o root.
2: Este código se lanzará cuando se ejecute el script sin argumentos o con un argumento inválido.
3: Este código se lanzará cuando se ejecute el script sin haber inicializado la herramienta.
4: Este código se lanzará cuando se rechace la instalación de alguna dependencia necesaria.
5: Este código se lanzará cuando se establezca algún dato inválido en el fichero de credenciales.
6: Este código se lanzará cuando no haya ningún script a ejecutar en el directorio de scripts.
7: Este código se lanzará cuando no haya ningún cliente a ejecutar scripts en el fichero de targets.
'


# CONSTANTES DEL SCRIPT
RUNNING_PATH="$(cd "$(dirname "$0")"; pwd)"
SCRIPTS_PATH="$RUNNING_PATH/scripts"
DATA_PATH="$RUNNING_PATH/data"
LOGS_PATH="$RUNNING_PATH/logs"
LOGS_HISTORY_PATH="$LOGS_PATH/history"


: '
Esta función genera una cadena con la fecha actual exacta.
'
generate_timestamp() {
    date +"%Y-%m-%dT%H%M%S%z" | sed 's/+/-/'
}


: '
Esta función recibe como parámetros una cadena con el dominio a obtener
la IP y un número entero, el cual será la cantidad de intentos que
ejecutará para poder obtener la dirección IP.
'
resolve_domain() {
  local domain=$1
  local timeout=$2

  local current_ip=$(dig +short "$domain" | grep -v "communications error")

  tries=1
  while [ "$current_ip" == "" ] && [ "$tries" -lt "$timeout" ]; do
    current_ip=$(dig +short "$domain" | grep -v "communications error")
    ((tries++))
  done

  # Puede devolver una cadena vacía o la dirección IP
  echo "$current_ip"
}


: '
Esta función recibe como parámetros un array vacío, el cual será
rellenado con las rutas de cada script del directorio de scripts.

Para evitar problemas, esta función solo cargará scripts en la
raíz del directorio de scripts.
'
load_scripts() {
  local -n scripts_list=$1
  local scripts_folder_content=$(find $SCRIPTS_PATH/* -maxdepth 0 -type f 2>/dev/null)

  if [[ "$(echo "$scripts_folder_content" | grep -v '^$' | wc -l)" -le 0 ]]; then
    echo "ERROR: No hay scripts para que los clientes los ejecuten."
    exit 6
  fi

  for script in $scripts_folder_content; do
    scripts_list+=("$script")
  done
}


: '
Esta función recibe como parámetros un array vacío, el cual será
rellenado con las ips o dominios de los clientes para lanzarles
scripts.

Si hay algún cliente repetido solo se ejecutarán los scripts
una única vez.

El fichero que contiene las ips está en: data/.targets
'
load_targets() {
  local -n targets_list=$1
  local targets_file_content=$(awk '!seen[$0]++' "$DATA_PATH/.targets")
  local IP_REGEX='^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))$'
  local current_ip
  local current_domain_ip

  if [ "$(echo "$targets_file_content" | grep -v '^$' | wc -l)" -eq 0 ]; then
    echo "ERROR: No hay ips de clientes para que ejecuten los scripts."
    exit 7
  fi

  for target in $targets_file_content; do
    local index=0
    local length=${#targets_list[@]}
    local found=false

    while [ "$index" -lt "$length" ] && [ "$found" = false ]; do
      current_target=${targets_list[$index]}

      if [[ $target =~ $IP_REGEX ]]; then
        # comprobar dominios para ver si tienen la misma ip que target.
        if ! [[ $current_target =~ $IP_REGEX ]]; then
          current_ip="$(resolve_domain "$current_target")"

          if [ "$target" == "$current_ip" ]; then
            found=true
          fi
        fi
      else
        # comprobar ips para ver si tienen la misma ip que el dominio en target
        current_domain_ip="$(resolve_domain "$target")"

        if [[ $current_target =~ $IP_REGEX ]]; then
          current_ip="$current_target"
        else
          current_ip="$(resolve_domain "$current_target")"
        fi

        if [ "$current_domain_ip" == "$current_ip" ]; then
          found=true
        fi
      fi

        ((index++))
    done


    if [ "$found" = false ]; then
      targets_list+=("$target")
    fi
  done
}


: '
Esta función recibe como parámetros un array vacío el cual será
rellenado con las rutas de cada log del directorio proporcionado,
una cadena que será el directorio donde estarán los logs, y una
cadena con el nombre del script para cargar solo los logs de ese
script.

Para evitar problemas, esta función solo cargará logs en la
raíz del directorio proporcionado.
'
load_logs() {
  local -n logs_list=$1
  local logs_folder_content=$(find $2/*_$3.log -maxdepth 0 -type f 2>/dev/null)

  if [[ "$(echo "$logs_folder_content" | grep -v '^$' | wc -l)" -le 0 ]]; then
    echo "WARN: No hay logs para el script \"$3\"."
  else
    for log in $logs_folder_content; do
      logs_list+=("$log")
    done
  fi
}


: '
FLUJO PRINCIPAL DEL SCRIPT
'
main() {
  # Comprueba si los ficheros necesarios existen, si no cierra el script y
  # recomienda al usuario que inicie la herramienta correctamente.
  if [ ! -f "$DATA_PATH/.remote-credentials" ] || [ ! -f "$DATA_PATH/.targets" ] ||
  [ ! -d "$SCRIPTS_PATH" ] || [ ! -d "$LOGS_PATH" ] || [ ! -d "$LOGS_HISTORY_PATH" ]; then
    echo "ERROR: Debes iniciar la herramienta usando el argumento \"init\" antes de hacer esto."
    exit 3
  fi

  # Comprueba si la dependencia "screen" está instalada. En caso contrario,
  # preguntará al usuario si la quiere instalar, y en caso de no instalarla,
  # el script finalizará.
  if ! command -v screen &> /dev/null; then
    echo "INFO: El paquete screen servirá para ejecutar los scripts de manera asíncrona en los clientes."
    read -rp "INFO: El paquete screen no está instalado. ¿Quieres instalarlo? [Y/N]: " opt

    if [ "${opt^^}" == "Y" ]; then
      sudo apt-get update
      sudo apt-get -y install screen
    else
      echo "ERROR: Para hacer más rápido la ejecución de scripts se necesita ese paquete."
      exit 4
    fi
  fi

  # Recupera de los ficheros los datos necesarios para realizar la
  # ejecución de scripts en todos los clientes configurados.
  SCRIPTS=()
  TARGETS=()
  load_scripts SCRIPTS
  load_targets TARGETS
  REMOTE_USER="$(grep "REMOTE_USER" "$DATA_PATH/.remote-credentials" | cut -d":" -f2)"
  REMOTE_PASS="$(grep "REMOTE_PASS" "$DATA_PATH/.remote-credentials" | cut -d":" -f2)"
  REMOTE_KEY_PATH="$(grep "REMOTE_KEY_PATH" "$DATA_PATH/.remote-credentials" | cut -d":" -f2)"
  LOGS_TIMESTAMP="$(generate_timestamp)"
  amount_executed_scripts=0

  # Si no han establecido algún campo del fichero de credenciales,
  # terminará el programa.
  if [ "$REMOTE_USER" == "" ] || [ "$REMOTE_PASS" == "" ] || [ "$REMOTE_KEY_PATH" == "" ]; then
    echo "ERROR: Alguna de las credenciales establecidas en el fichero de credenciales no es válida."
    exit 5
  fi

  # Si la SSH KEY establecida en el fichero de credenciales no
  # existe en el sistema, el programa terminará.
  if [ ! -f "$REMOTE_KEY_PATH" ]; then
    echo "ERROR: La SSH KEY \"$REMOTE_KEY_PATH\" establecida en el fichero de config no existe en el sistema."
    exit 5
  fi

  for script in "${SCRIPTS[@]}"; do
    script_name=${script##*/}
    script_sort_name="${script_name%.sh}"
    echo "---------------   >>>   EJECUTANDO SCRIPT \"$script_name\"   <<<   ---------------"

    for client in "${TARGETS[@]}"; do
      current_logfile="$LOGS_PATH/$client\_$script_name.log" # Genera el nombre del log.

      # En caso de que el fichero de log ya exista, lo borraremos para
      # que no se junten logs de antiguas ejecuciones.
      if [ -f "$current_logfile" ]; then
        rm "$current_logfile"
      fi

      # Comprueba que el cliente está online.
      if ping -c 1 "$client" &> /dev/null; then
        encoded_script=$(base64 -w 0 "$script") # Codifica el contenido del script en base64.

        # Inicia el proceso de ejecución del script en el cliente remoto mediante el
        # uso del paquete screen, para hacer esta ejecución en segundo plano de
        # manera asíncrona.
        echo "INFO: Ejecutando script \"$script_name\" en el cliente \"$client\"..."
        screen -L -Logfile "$current_logfile" -dmS "$client-$script_name" bash -c "
        echo '$REMOTE_PASS' | ssh -i '$REMOTE_KEY_PATH' -tt '$REMOTE_USER@$client' \"echo '$encoded_script' | base64 -d | sudo bash -s\" && echo 'RUN-STATUS: OK' || echo 'RUN-STATUS: FAILED'
        "
      else
        echo "WARN: El cliente $client está offline o no se encuentra accesible. Saltando al siguiente cliente..."
      fi
    done

    # Espera a que todas las ejecuciones del script actual hayan terminado.
    echo -e "\nINFO: Esperando a que el script \"$script_name\" termine de ejecutarse en todos los clientes..."
    while [ -n "$(screen -ls | grep -v -E '(Sockets|Socket|screen|^[[:space:]]*$)' | grep "$script_name")" ]; do
      sleep 2
    done

    # Recupera los logs de ejecución de todos los clientes para el script
    # actual y los procesa para dar un estado de ejecución aproximado.
    RUN_LOGS=()
    load_logs RUN_LOGS "$LOGS_PATH" "$script_name"
    for log in "${RUN_LOGS[@]}"; do
      client=$(echo "${log##*/}" | cut -d"_" -f1)
      sed -i '1d' "$log" # Eliminamos la primera linea del log, donde suele aparecer la contraseña remota en texto plano.

      # Para considerar que un script se ha ejecutado correctamente, el log debe contener
      # al menos la cadena "EXEC-STATUS: OK", ya que esto quiere decir que se ha logrado
      # enviar el script al cliente y que debería de haber ido bien.
      #
      # Para garantizar esta funcionalidad, se deberá programar todos los scripts, de
      # manera que cuando haya fallado algo, se deberá imprimir por pantalla la cadena
      # "EXEC-STATUS: FAILED" y finalizar el script. Si se ejecutó correctamente, la
      # última instrucción de cualquier script será un "echo EXEC-STATUS: OK".
      if grep -q "RUN-STATUS: FAILED" "$log" && ! grep -q "EXEC-STATUS:" "$log"; then
        echo "ERROR: No se pudo lanzar el script \"$script_name\" en el cliente \"$client\"."
      else
        if grep -q "EXEC-STATUS: OK" "$log"; then
          echo "INFO: El script \"$script_name\" se logró lanzar y ejecutar con éxito en el cliente \"$client\"."
        else
          echo "WARN: El script \"$script_name\" se logró lanzar en el cliente \"$client\" pero hubo algún problema" \
          "en la ejecución. Revisa el log \"$LOGS_HISTORY_PATH/$script_sort_name/$LOGS_TIMESTAMP/${log##*/}\"."
        fi
      fi
    done

    # Comprueba que el script se ha podido ejecutar comprobando si ha dejado logs
    # o no. Si no deja logs, entonces no creará la carpeta en el historial.
    if [ ${#RUN_LOGS[@]} -gt 0 ]; then
      # Crea el directorio en el historial de logs donde se almacenarán los logs
      # de la ejecución de un script con su hora de ejecución.
      if [ ! -d "$LOGS_HISTORY_PATH/$script_sort_name/$LOGS_TIMESTAMP" ]; then
        mkdir -p "$LOGS_HISTORY_PATH/$script_sort_name/$LOGS_TIMESTAMP"
      fi

      # Mueve los logs correspondientes al directorio correspondiente del historial.
      mv $LOGS_PATH/*_$script_name.log "$LOGS_HISTORY_PATH/$script_sort_name/$LOGS_TIMESTAMP/"
    fi

    ((amount_executed_scripts++))

    if [ ${#SCRIPTS[@]} -gt 1 ] && [ "$amount_executed_scripts" -lt ${#SCRIPTS[@]} ]; then
      echo -e "\n"
    fi
  done
}


: '
Este método permite instalar una SSH KEY en todos los clientes establecidos
en el fichero de "data/.targets". Esto permitirá automatizar el login en
los clientes a la hora de ejecutar los scripts.

Esta parte del script requiere tener instalado las siguientes dependencias:
  - sshpass: Sirve para autenticarse de manera automática a la hora de
             copiar la SSH KEY en el cliente.
'
init-targets() {
  # Comprueba si los ficheros necesarios existen, si no cierra el script y
  # recomienda al usuario que inicie la herramienta correctamente.
  if [ ! -f "$DATA_PATH/.remote-credentials" ] || [ ! -f "$DATA_PATH/.targets" ]; then
    echo "ERROR: Debes iniciar la herramienta usando el argumento \"init\" antes de hacer esto."
    exit 3
  fi

  # Comprueba si la dependencia "sshpass" está instalada. En caso contrario,
  # preguntará al usuario si la quiere instalar, y en caso de no instalarla,
  # el script finalizará.
  if ! command -v sshpass &> /dev/null; then
      echo "INFO: El paquete sshpass servirá para enviar la contraseña a los clientes para instalar la SSH KEY."
      read -rp "INFO: El paquete sshpass no está instalado. ¿Quieres instalarlo? [Y/N]: " opt

      if [ "${opt^^}" == "Y" ]; then
        sudo apt-get update
        sudo apt-get -y install sshpass
      else
        echo "ERROR: Para hacer la instalación automática de la SSH KEY en los clientes se necesita ese paquete."
        exit 4
      fi
  fi

  # Recupera de los ficheros los datos necesarios para instalar
  # la SSH KEY en los clientes.
  TARGETS=()
  load_targets TARGETS
  REMOTE_USER="$(grep "REMOTE_USER" "$DATA_PATH/.remote-credentials" | cut -d":" -f2)"
  REMOTE_PASS="$(grep "REMOTE_PASS" "$DATA_PATH/.remote-credentials" | cut -d":" -f2)"
  REMOTE_KEY_PATH="$(grep "REMOTE_KEY_PATH" "$DATA_PATH/.remote-credentials" | cut -d":" -f2)"

  # Si la SSH KEY establecida en el fichero de credenciales no
  # existe en el sistema, el programa terminará.
  if [ ! -f "$REMOTE_KEY_PATH" ]; then
    echo "ERROR: La SSH KEY \"$REMOTE_KEY_PATH\" establecida en el fichero de config no existe en el sistema."
    exit 5
  fi

  echo -e "INFO: Instalando la SSH KEY en los clientes...\n"
  for client in "${TARGETS[@]}"; do
    # La opción "-o StrictHostKeyChecking=no" solo debería usarse en
    # redes de equipos controladas, ya que el uso de ese parámetro
    # puede dar paso a un man in the middle.
    sshpass -p "$REMOTE_PASS" ssh-copy-id -i "$REMOTE_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER"@"$client"
  done

  echo "INFO: SSH KEY instalada en todos los clientes."
}


: '
Este método permite inicializar la herramienta de una manera sencilla
y automática. Hay que tener en cuenta que todos los ficheros tienen
valores por defecto que se deben cambiar para que el script funcione.
'
init() {
  echo "INFO: Iniciando el entorno de la herramienta..."

  if [ ! -d "$SCRIPTS_PATH" ]; then
    mkdir -p "$SCRIPTS_PATH"
  fi

  if [ ! -d "$DATA_PATH" ]; then
    mkdir -p "$DATA_PATH"
  fi

  if [ ! -f "$DATA_PATH/.remote-credentials" ]; then
    local content="REMOTE_USER:defaultUser\n"
    content+="REMOTE_PASS:defaultPass\n"
    content+="REMOTE_KEY_PATH:/home/profesor/.ssh/id_rsa"

    echo -e "$content" > "$DATA_PATH/.remote-credentials"
    chmod 600 "$DATA_PATH/.remote-credentials"
  fi

  if [ ! -f "$DATA_PATH/.targets" ]; then
    echo -e "1.1.1.1\n8.8.8.8" > "$DATA_PATH/.targets"
    chmod 600 "$DATA_PATH/.targets"
  fi

  if [ ! -d "$LOGS_PATH" ]; then
    mkdir -p "$LOGS_PATH"
  fi

  if [ ! -d "$LOGS_HISTORY_PATH" ]; then
    mkdir -p "$LOGS_HISTORY_PATH"
  fi

  echo "INFO: Entorno iniciado correctamente."
  echo "INFO: Ahora prueba a iniciar los clientes usando el argumento \"init-targets\" o a ejecutar la herramienta con el argumento \"start\"."
}


if [ "$EUID" -eq 0 ]; then
  echo "ERROR: Debes ejecutar este script sin sudo o root"
  exit 1
fi

if [ "$#" -ne 1 ]; then
  echo "Uso: $0 init | init-targets | start"
  exit 2
fi

if [ "$1" == "init" ]; then
  init
elif [ "$1" == "init-targets" ]; then
  init-targets
elif [ "$1" == "start" ]; then
  main
else
  echo "Uso: $0 init | init-targets | start"
  exit 2
fi