# Sistema de Balanceo de Carga MySQL con Nginx

## Descripción del Proyecto

Este proyecto implementa un sistema de **balanceo de carga para bases de datos MySQL** utilizando **Nginx** como proxy TCP (capa 4). El objetivo principal es optimizar el rendimiento mediante la separación de operaciones de **lectura** y **escritura**, distribuyendo la carga entre múltiples nodos de base de datos.

### Características principales:
- **Replicación maestro-esclavo**: 1 nodo maestro + 2 nodos esclavos con replicación asíncrona basada en binlog
- **Separación de tráfico**: Escrituras al maestro, lecturas distribuidas entre 3 nodos
- **Balanceo round-robin**: Distribución equitativa de conexiones de lectura
- **Alta disponibilidad**: Tolerancia a fallos de nodos esclavos
- **Provisioning automatizado**: Despliegue completo con Vagrant
- **Herramientas de benchmarking**: Sysbench integrado para pruebas de rendimiento

---

## Arquitectura del Sistema

El sistema implementa una arquitectura de **replicación maestro-esclavo** con **separación de tráfico de lectura y escritura** mediante un balanceador de carga Nginx.

### Componentes del Sistema:

| Componente | IP | Hostname | Puerto SSH | Rol |
|------------|-----|----------|------------|-----|
| **MySQL Master** | 192.168.70.10 | mysql-master | 2210 | Escrituras y fuente de replicación |
| **MySQL Slave 1** | 192.168.70.11 | mysql-slave | 2211 | Réplica para lecturas |
| **MySQL Slave 2** | 192.168.70.12 | mysql-slave2 | 2212 | Réplica para lecturas |
| **Nginx Balancer** | 192.168.70.13 | nginx-balancer | 2213 | Proxy TCP (puertos 3307/3308) |
| **Cliente** | 192.168.70.14 | client | 2214 | Herramientas de prueba |

### Cómo Funciona la Arquitectura:

#### 1. **Nodo Maestro (Master)**
El nodo maestro MySQL (192.168.70.10) es el único que acepta operaciones de **escritura** (INSERT, UPDATE, DELETE). Todas las modificaciones se registran en el **binary log (binlog)** que funciona como el diario de cambios de la base de datos. El maestro tiene habilitada la replicación y crea usuarios específicos para que los slaves puedan conectarse y leer el binlog.

**Configuración clave:**
- `server-id = 1` - Identificador único en el clúster
- `log_bin` habilitado - Registra todas las transacciones
- `binlog_format = ROW` - Formato de replicación basado en filas
- Bases de datos: `test` y `sbtest` creadas automáticamente

#### 2. **Nodos Esclavos (Slaves)**
Los dos nodos esclavos (192.168.70.11 y 192.168.70.12) están configurados en modo **read-only** y se conectan al maestro para replicar datos. Cada slave lee continuamente el binlog del maestro, almacena los eventos en su **relay log** y los aplica a su base de datos local. Esto mantiene los slaves sincronizados con el maestro de forma asíncrona.

**Configuración clave:**
- `server-id = 2` y `server-id = 3` - IDs únicos por slave
- `read_only = ON` - Previene escrituras directas
- `relay_log` habilitado - Procesa eventos de replicación
- Replicación configurada automáticamente con `CHANGE MASTER TO`

**Proceso de replicación:**
1. Slave conecta al maestro usando credenciales `replicator`
2. Slave solicita eventos del binlog desde una posición específica
3. Maestro envía eventos al slave
4. Slave escribe eventos en relay log
5. Slave SQL thread lee relay log y aplica cambios localmente

#### 3. **Balanceador Nginx**
Nginx (192.168.70.13) actúa como **proxy TCP de capa 4** que intercepta conexiones MySQL y las redirige según el tipo de operación. Usa el módulo **stream** para manejar conexiones TCP sin interpretar el protocolo MySQL.

**Configuración de puertos:**
- **Puerto 3307 (Lecturas)**: Define un upstream pool llamado `mysql_read` con los 3 nodos MySQL (maestro + 2 slaves). Nginx distribuye las conexiones entrantes usando el algoritmo **round-robin**, enviando cada nueva conexión al siguiente nodo de la lista de forma cíclica. Esto distribuye la carga de lecturas equitativamente.

- **Puerto 3308 (Escrituras)**: Define un upstream pool llamado `mysql_write` con solo el nodo maestro. Todas las conexiones de escritura se envían directamente al maestro para mantener la consistencia de datos.

**Ventajas del balanceador:**
- Separación transparente para el cliente (solo cambia el puerto)
- Distribución automática de carga de lecturas
- Punto único de acceso a la base de datos
- Simplicidad de configuración

#### 4. **Cliente de Pruebas**
La VM cliente (192.168.70.14) tiene instaladas herramientas para probar y medir el rendimiento:
- **mysql-client**: Para ejecutar consultas SQL interactivas
- **sysbench**: Para pruebas de carga y benchmarking

**Flujo de trabajo del cliente:**
- Para **escrituras**: Conecta a `192.168.70.13:3308` → Nginx lo dirige al maestro
- Para **lecturas**: Conecta a `192.168.70.13:3307` → Nginx distribuye entre los 3 nodos

### Flujo Completo de Datos:

**Escritura (INSERT/UPDATE/DELETE):**
1. Cliente envía query de escritura al balanceador (puerto 3308)
2. Nginx recibe la conexión y la reenvía al maestro (192.168.70.10:3306)
3. Maestro ejecuta la transacción y registra cambios en el binlog
4. Maestro confirma la transacción al cliente (vía Nginx)
5. Slaves leen el binlog de forma asíncrona y replican los cambios

**Lectura (SELECT):**
1. Cliente envía query de lectura al balanceador (puerto 3307)
2. Nginx selecciona un nodo del pool usando round-robin (puede ser maestro, slave1 o slave2)
3. El nodo seleccionado ejecuta la query y devuelve resultados
4. Nginx reenvía la respuesta al cliente
5. Próxima lectura irá al siguiente nodo en la rotación

**Replicación continua:**
- Ocurre en segundo plano de forma asíncrona
- Los slaves están típicamente sincronizados (lag mínimo: 0-1 segundos)
- Se puede verificar con `SHOW SLAVE STATUS` en cada slave

### Beneficios de esta Arquitectura:

1. **Escalabilidad horizontal**: Agregar más slaves aumenta la capacidad de lectura
2. **Distribución de carga**: Las lecturas se reparten entre 3 nodos, reduciendo carga individual
3. **Separación de operaciones**: Escrituras no compiten con lecturas por recursos
4. **Alta disponibilidad**: Si un slave falla, el sistema sigue funcionando con capacidad reducida
5. **Simplicidad**: Arquitectura probada y fácil de entender
6. **Costo-efectivo**: No requiere hardware especializado

---

## Estructura del Proyecto

```
proyecto_telematicos/
├── Vagrantfile                    # Definición de las 5 máquinas virtuales
├── config/                        # Archivos de configuración
│   ├── my.conf.master            # Configuración MySQL del maestro (server-id=1, binlog)
│   ├── my.conf.slave             # Configuración MySQL del slave1 (server-id=2, read_only)
│   ├── my.conf.slave2            # Configuración MySQL del slave2 (server-id=3, read_only)
│   └── conf.balancer             # Configuración Nginx (stream module, upstreams)
├── provision/                     # Scripts de provisioning automatizado
│   ├── master.sh                 # Setup del maestro (usuarios, bases de datos, binlog)
│   ├── slave.sh                  # Setup del slave1 (replicación, permisos)
│   ├── slave2.sh                 # Setup del slave2 (replicación, permisos)
│   ├── balancer.sh               # Setup de Nginx (instalación, configuración)
│   └── client.sh                 # Setup del cliente (mysql-client, sysbench, prepare)
├── README.md                      # Este archivo - Documentación principal
├── PRUEBAS_SISTEMA.md            # Guía detallada de pruebas (7 casos de prueba)
└── REFERENCIA_TECNICA.md         # Referencia técnica de configuración
```

---

## Instalación y Puesta en Marcha

### 1. Clonar el repositorio

```bash
git clone https://github.com/AlejoBI/proyecto_telematicos.git
cd proyecto_telematicos
```

### 2. Requisitos Previos

- **Vagrant** >= 2.0 ([Descargar](https://www.vagrantup.com/downloads))
- **VirtualBox** >= 6.0 ([Descargar](https://www.virtualbox.org/wiki/Downloads))
- **Sistema operativo**: Windows, macOS o Linux
- **RAM mínima recomendada**: 8 GB (el proyecto usa ~4-5 GB)
- **Espacio en disco**: ~10 GB libres

### 3. Iniciar el entorno completo

```powershell
vagrant up
```

**Tiempo estimado**: 10-15 minutos para el provisioning completo de las 5 VMs.

Durante el proceso, Vagrant:
1. Descarga la imagen base de Ubuntu 22.04
2. Crea las 5 máquinas virtuales
3. Instala y configura MySQL en Master y Slaves
4. Configura la replicación automáticamente
5. Instala y configura Nginx en el Balancer
6. Instala herramientas de prueba en el Cliente
7. Prepara datos iniciales con Sysbench

### 4. Verificar el estado

```powershell
vagrant status
```

Salida esperada:
```
Current machine states:

mysql_master          running (virtualbox)
mysql_slave           running (virtualbox)
mysql_slave2          running (virtualbox)
nginx_balancer        running (virtualbox)
client                running (virtualbox)
```

---

## Configuración Técnica del Sistema

### MySQL Master (192.168.70.10)
- **Binlog habilitado**: Registra todas las escrituras para replicación
- **Usuarios de replicación**: `replicator@192.168.70.11` y `replicator@192.168.70.12`
- **Bases de datos**: `test` (con datos de prueba) y `sbtest` (para sysbench)
- **Configuración**: `config/my.conf.master` (server-id=1, binlog_format=ROW)

### MySQL Slaves (192.168.70.11 y 192.168.70.12)
- **Read-only**: Previene escrituras directas
- **Replicación automática**: Configurada durante provisioning
- **Relay logs**: Procesan eventos del binlog del maestro
- **Configuración**: `config/my.conf.slave` y `config/my.conf.slave2` (server-id=2 y 3)

### Nginx Balancer (192.168.70.13)
- **Módulo stream**: Proxy TCP (capa 4)
- **Upstream mysql_read**: 3 nodos (192.168.70.10, .11, .12) - round-robin
- **Upstream mysql_write**: 1 nodo (192.168.70.10) - solo maestro
- **Configuración**: `config/conf.balancer`

### Cliente (192.168.70.14)
- **mysql-client**: Para consultas SQL interactivas
- **sysbench**: Herramienta de benchmarking de MySQL
- **Datos preparados**: 4 tablas con 10,000 registros cada una

---

## Verificación Rápida del Sistema

### Conectar por SSH a las VMs

```powershell
# Desde Windows PowerShell:
vagrant ssh mysql_master    # o: ssh -p 2210 vagrant@127.0.0.1
vagrant ssh mysql_slave     # o: ssh -p 2211 vagrant@127.0.0.1
vagrant ssh mysql_slave2    # o: ssh -p 2212 vagrant@127.0.0.1
vagrant ssh nginx_balancer  # o: ssh -p 2213 vagrant@127.0.0.1
vagrant ssh client          # o: ssh -p 2214 vagrant@127.0.0.1
```

### Verificar replicación en los Slaves

```bash
# Conectar a cualquier slave y ejecutar:
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master"
```

**Salida esperada**:
```
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Seconds_Behind_Master: 0
```

### Verificar Nginx Balancer

```bash
# Conectar al balanceador:
vagrant ssh nginx_balancer

# Verificar estado:
sudo systemctl status nginx
sudo ss -tlpn | grep -E ':3307|:3308'
```

Debe mostrar que Nginx está escuchando en **puerto 3307** (lecturas) y **puerto 3308** (escrituras).

---

## Pruebas de Rendimiento con Sysbench

### Acceder al cliente

```bash
vagrant ssh client
```

### Pruebas de Escritura (puerto 3308 - solo maestro)

```bash
sysbench /usr/share/sysbench/oltp_write_only.lua \
--mysql-host=192.168.70.13 \
--mysql-port=3308 \
--mysql-user=root \
--mysql-password=admin \
--mysql-db=sbtest \
--tables=4 \
--table-size=10000 \
--threads=8 \
--time=30 \
--report-interval=5 \
run
```

### Pruebas de Lectura (puerto 3307 - balanceado entre 3 nodos)

```bash
sysbench /usr/share/sysbench/oltp_read_only.lua \
--mysql-host=192.168.70.13 \
--mysql-port=3307 \
--mysql-user=root \
--mysql-password=admin \
--mysql-db=sbtest \
--tables=4 \
--table-size=10000 \
--threads=8 \
--time=30 \
--report-interval=5 \
run
```

### Métricas importantes a observar:

- **Transactions per second (TPS)**: Mayor es mejor
- **Latency (avg/min/max)**: Menor es mejor
- **95th percentile latency**: Indicador de estabilidad
- **Errors**: Debe ser 0

---

## Pruebas Manuales de Balanceo

### Verificar distribución de lecturas

Desde el cliente, ejecutar múltiples lecturas y ver a qué servidor se conecta:

```bash
for i in {1..15}; do
  mysql -uroot -padmin -h 192.168.70.13 -P3307 -e "SELECT @@hostname, NOW();" 2>/dev/null | tail -n 1
done
```

**Resultado esperado**: Verás que las conexiones se distribuyen entre `mysql-master`, `mysql-slave` y `mysql-slave2` aproximadamente en partes iguales.

### Insertar datos y verificar replicación

```bash
# Insertar un registro con timestamp:
TIMESTAMP=$(date +%s)
mysql -uroot -padmin -h 192.168.70.13 -P3308 -e "USE test; INSERT INTO test (name) VALUES ('test_$TIMESTAMP');"

# Leer desde el balanceador (lecturas):
mysql -uroot -padmin -h 192.168.70.13 -P3307 -e "USE test; SELECT * FROM test WHERE name LIKE 'test_%' ORDER BY id DESC LIMIT 5;"
```

El dato insertado debe aparecer en las lecturas, confirmando que la replicación funciona.

---

## Monitoreo del Sistema

### Logs de Nginx (ver distribución de conexiones)

```bash
# Conectar al balanceador:
vagrant ssh nginx_balancer

# Ver logs en tiempo real:
sudo tail -f /var/log/nginx/error.log
```

### Estado de replicación en Slaves

```bash
# Conectar a slave1 o slave2:
vagrant ssh mysql_slave

# Ver estado completo:
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G"

# Ver solo métricas clave:
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master|Last_IO_Error|Last_SQL_Error"
```

### Conexiones activas en MySQL

```bash
# En cualquier nodo MySQL:
mysql -uroot -padmin -e "SHOW PROCESSLIST;"
```

---

## Gestión del Entorno

### Detener las VMs

```powershell
vagrant halt
```

### Reiniciar las VMs

```powershell
vagrant up
```

### Destruir completamente el entorno

```powershell
vagrant destroy -f
```

### Reconstruir desde cero

```powershell
vagrant destroy -f
vagrant up
```

---

## Documentación Adicional

### Para pruebas detalladas:
Consulta **PRUEBAS_SISTEMA.md** que incluye:
- 7 casos de prueba paso a paso
- Comandos completos de sysbench para diferentes escenarios
- Simulación de fallos y recuperación
- Análisis de resultados y métricas

### Para referencia técnica:
Consulta **REFERENCIA_TECNICA.md** que incluye:
- Detalles de configuración de MySQL (binlog, replicación, usuarios)
- Detalles de configuración de Nginx (upstreams, proxying)
- Flujo de datos completo (escrituras, lecturas, replicación)
- Troubleshooting y solución de problemas comunes
- Consideraciones para producción

---

## Características Implementadas

- Replicación maestro-esclavo con MySQL binlog
- Balanceo de carga con Nginx (módulo stream)
- Separación de tráfico de lectura/escritura
- Provisioning automatizado con Vagrant
- Alta disponibilidad (tolerancia a fallo de 1 slave)
- Herramientas de benchmarking integradas (sysbench)
- Monitoreo de replicación y estado del sistema

---

## Autor y Contacto

**Proyecto**: Sistema de Balanceo de Carga MySQL con Nginx  
**Repositorio**: [github.com/AlejoBI/proyecto_telematicos](https://github.com/AlejoBI/proyecto_telematicos)  
**Propósito**: Proyecto académico - Demostración de balanceo de carga y replicación de bases de datos

---

Desarrollado para pruebas de rendimiento y análisis de arquitecturas distribuidas de bases de datos MySQL.
