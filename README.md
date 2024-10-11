# Remote Runner
Un script que permite ejecutar scripts en equipos remotos.


## Características
- Iniciador de la herramienta integrado.
- Instalación automática de dependencias. (Solicita permiso al usuario)
- Instalación automática de una clave SSH en los equipos remotos.
- Soporte completo para la utilización de dominios.
- Auto purga de duplicados del fichero de clientes.
- Ejecución de scripts de manera simultánea.
- Registro de logs de los scripts ejecutados.

 
## Usando la herramienta
### Paso 1:
Para ejecutar este script, primero deberás clonar el repositorio o descargártelo manualmente.
```bash
git clone https://github.com/davidgb8246/RemoteRunner
cd RemoteRunner/
```


### Paso 2:
Una vez clonado, ejecuta el script con el argumento `init` para que se creen
todo el conjunto de directorios de manera automática.
```bash
/bin/bash remoteRunner.sh init
```

Esta parte creará el siguiente conjunto de directorios:<br>
```yaml
.
├── data/
│   ├── .remote-credentials # Contendrá las credenciales.
│   └── .targets # Contendrá las ips de los clientes.
├── logs/
│   └── history/ # Contendrá todos los logs de cada script por separado.
├── scripts/ # Contendrá todos los scripts a ejecutar.
└── remoteRunner.sh
```


### Paso 3:
Cuando se termine de inicializar la herramienta, debes editar los 
ficheros `data/.remote-credentials` y `data/.targets` con las 
credenciales y las ips de los clientes respectivamente.

Ejemplo de configuración del fichero `data/.remote-credentials`:
```yaml
REMOTE_USER:usuarioRemoto
REMOTE_PASS:1234567890
REMOTE_KEY_PATH:/home/prueba/.ssh/id_rsa
```

Donde `REMOTE_USER` es el usuario que se usará a la hora de conectarse con los
equipos remotos (debe tener sudo), `REMOTE_PASS` es la contraseña del usuario
previamente mencionado, `REMOTE_KEY_PATH` es la ruta absoluta de donde se 
encuentra la clave SSH que se instalará y usará a la hora de ejecutar los
scripts.<br><br>

Ejemplo de configuración del fichero `data/.targets`:
```yaml
pc-01.ejemplo.com
pc-02.ejemplo.com
pc-03.ejemplo.com
192.168.15.2
192.168.15.3
192.168.15.4
```

Donde cada línea representa la **dirección IP** o **dominio** de uno de los
clientes. Si hay varias entradas que acaban apuntando al mismo cliente,
los scripts solo se ejecutarán una vez por cada uno de los clientes.


### Paso 4 (opcional):
Una vez configurado la herramienta, podemos ejecutar el script con el argumento
`init-targets` para instalar la clave SSH en todos los clientes. Este paso se
puede saltar y hacerlo manualmente o con otros métodos.
```bash
/bin/bash remoteRunner.sh init-targets
```


### Paso 5:
Después, mete los scripts que quieras ejecutar en el directorio `scripts/`.


### Paso 6:
Por último, ya se podría ejecutar el script con el argumento `start` para empezar
a ejecutar todos los scripts en todos los clientes.
```bash
/bin/bash remoteRunner.sh start
```



## Colaboradores ✨
- [davidgb8246](https://github.com/davidgb8246)<br><br>

Copyright (C) 2024
