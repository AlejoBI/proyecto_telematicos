# Proyecto 3: Balanceo de Carga MySQL + Nginx
## Documentación técnica de configuración

---

## Descripción del sistema

Este proyecto implementa un sistema de balanceo de carga para bases de datos MySQL utilizando Nginx como proxy TCP (capa 4). La arquitectura separa las operaciones de **lectura** y **escritura** para optimizar el rendimiento y distribuir la carga entre múltiples nodos de base de datos.

### Componentes principales:
1. **MySQL Master** - Nodo maestro que maneja todas las escrituras y actúa como fuente de replicación
2. **MySQL Slaves (2)** - Nodos esclavos que replican datos del maestro y atienden lecturas
3. **Nginx Balancer** - Proxy TCP que distribuye las conexiones según el tipo de operación
4. **Cliente** - Máquina de pruebas con herramientas de benchmarking (sysbench, mysql-client)

### Características:
- Replicación maestro-esclavo asíncrona basada en binlog
- Balanceo round-robin para operaciones de lectura entre 3 nodos
- Separación de tráfico: lecturas distribuidas, escrituras al maestro
- Provisioning automatizado con Vagrant y shell scripts
- Alta disponibilidad mediante múltiples nodos de lectura

---

## Tabla de IPs y puertos SSH

| Máquina | IP | Hostname | Puerto SSH | Rol |
|---------|-----|----------|------------|-----|
| **Maestro** | 192.168.70.10 | mysql-master | 2210 | MySQL Master - Escrituras y replicación |
| **Esclavo 1** | 192.168.70.11 | mysql-slave | 2211 | MySQL Slave - Lecturas y réplica |
| **Esclavo 2** | 192.168.70.12 | mysql-slave2 | 2212 | MySQL Slave - Lecturas y réplica |
| **Balanceador** | 192.168.70.13 | nginx-balancer | 2213 | Nginx TCP proxy (puertos 3307/3308) |
| **Cliente** | 192.168.70.14 | client | 2214 | VM para pruebas (mysql-client, sysbench) |

---

## Puertos del balanceador Nginx

- **Puerto 3307** - Lecturas (balanceo round-robin entre 192.168.70.10, .11 y .12)
- **Puerto 3308** - Escrituras (solo maestro 192.168.70.10)

---

## Configuración de MySQL

### MySQL Master (192.168.70.10)

**Archivo de configuración**: `config/my.conf.master`

Configuraciones clave:
- `server-id = 1` - Identificador único en el clúster de replicación
- `log_bin = /var/log/mysql/mysql-bin.log` - Habilita binary logging para replicación
- `binlog_format = ROW` - Formato de binlog basado en filas (más seguro)
- `bind-address = 0.0.0.0` - Permite conexiones desde cualquier IP

**Bases de datos creadas automáticamente**:
- `test` - Base de datos para pruebas con tabla inicial
- `sbtest` - Base de datos para benchmarks con sysbench

**Script de provisioning**: `provision/master.sh`
- Instala MySQL Server
- Configura replicación (usuarios replicator)
- Crea usuarios de acceso remoto con permisos específicos
- Inicializa bases de datos y datos de prueba

### MySQL Slaves (192.168.70.11 y 192.168.70.12)

**Archivos de configuración**: 
- Slave1: `config/my.conf.slave` (server-id = 2)
- Slave2: `config/my.conf.slave2` (server-id = 3)

Configuraciones clave:
- `server-id` único por slave
- `read_only = ON` - Previene escrituras directas al slave
- `relay_log` - Logs para procesar eventos de replicación del maestro
- `bind-address = 0.0.0.0` - Permite conexiones remotas

**Scripts de provisioning**: `provision/slave.sh` y `provision/slave2.sh`
- Instalan MySQL Server
- Configuran replicación usando `CHANGE MASTER TO`
- Obtienen posición del binlog automáticamente desde el maestro
- Verifican estado de replicación (Slave_IO_Running, Slave_SQL_Running)
- Crean usuarios para acceso desde balanceador y cliente

---

## Configuración de Nginx

**Archivo de configuración**: `config/conf.balancer`

**Script de provisioning**: `provision/balancer.sh`

### Upstream pools:

**mysql_read** (puerto 3307):
```nginx
upstream mysql_read {
    server 192.168.70.10:3306;  # Maestro
    server 192.168.70.11:3306;  # Esclavo 1
    server 192.168.70.12:3306;  # Esclavo 2
}
```
- Algoritmo: round-robin (por defecto)
- Distribuye conexiones equitativamente entre los 3 nodos

**mysql_write** (puerto 3308):
```nginx
upstream mysql_write {
    server 192.168.70.10:3306;  # Solo maestro
}
```
- Todas las escrituras se dirigen únicamente al nodo maestro

### Características del proxy:
- Módulo `stream` de Nginx (proxy TCP, no HTTP)
- No interpreta el protocolo MySQL, solo hace forwarding de paquetes TCP
- No realiza health checks activos (detecta fallos al intentar conectar)
- Configuración de timeouts: `proxy_connect_timeout 1s`

---

## Usuarios MySQL creados

### En el Maestro (192.168.70.10):
| Usuario | Host | Contraseña | Permisos | Propósito |
|---------|------|------------|----------|-----------|
| root | localhost | admin | ALL | Administración local |
| root | 192.168.70.11 | admin | ALL | Acceso desde slave1 |
| root | 192.168.70.12 | admin | ALL | Acceso desde slave2 |
| root | 192.168.70.13 | admin | ALL | Acceso desde balanceador |
| replicator | 192.168.70.11 | replicator_pass | REPLICATION SLAVE | Replicación slave1 |
| replicator | 192.168.70.12 | replicator_pass | REPLICATION SLAVE | Replicación slave2 |

### En Slave1 y Slave2 (192.168.70.11 y .12):
| Usuario | Host | Contraseña | Permisos | Propósito |
|---------|------|------------|----------|-----------|
| root | localhost | admin | ALL | Administración local |
| root | 192.168.70.13 | admin | ALL | Acceso desde balanceador |
| root | 192.168.70.14 | admin | REPLICATION CLIENT | Verificar estado desde cliente |

**Principio de mínimo privilegio**: El cliente solo tiene permiso `REPLICATION CLIENT` en los slaves, suficiente para ejecutar `SHOW SLAVE STATUS` pero no para leer datos directamente. Todas las operaciones de datos deben pasar por el balanceador.

---

## Flujo de datos

### Escrituras:
1. Cliente se conecta a `192.168.70.13:3308`
2. Nginx reenvía la conexión a `192.168.70.10:3306` (maestro)
3. MySQL Master procesa el INSERT/UPDATE/DELETE
4. Cambios se registran en el binlog del maestro
5. Slaves leen el binlog y replican los cambios de forma asíncrona

### Lecturas:
1. Cliente se conecta a `192.168.70.13:3307`
2. Nginx selecciona un backend del pool `mysql_read` (round-robin)
3. Conexión se reenvía a uno de los 3 nodos MySQL
4. El nodo procesa la consulta SELECT y devuelve resultados

### Replicación:
1. Slave ejecuta `CHANGE MASTER TO` apuntando al maestro
2. Slave conecta al maestro como usuario `replicator`
3. Slave descarga eventos del binlog del maestro
4. Eventos se escriben al relay log del slave
5. Slave SQL thread aplica los eventos a su base de datos local
6. Estado monitoreado con `SHOW SLAVE STATUS`

---

## Comandos para levantar el entorno

### Opción 1: Levantar todo desde cero
```powershell
cd 'c:\Users\Gamer\Desktop\Repositories\proyecto_telematicos'
vagrant up
```

### Opción 2: Levantar máquinas individualmente (en orden)
```powershell
vagrant up mysql_master      # Primero el maestro
vagrant up mysql_slave       # Luego slave1
vagrant up mysql_slave2      # Luego slave2
vagrant up nginx_balancer    # Luego el balanceador
vagrant up client            # Finalmente el cliente
```

### Verificar estado de las VMs
```powershell
vagrant status
```

### Conectar por SSH a cada VM
```powershell
# Maestro
ssh -p 2210 vagrant@127.0.0.1
# O usar: vagrant ssh mysql_master

# Slave1
ssh -p 2211 vagrant@127.0.0.1

# Slave2
ssh -p 2212 vagrant@127.0.0.1

# Balanceador
ssh -p 2213 vagrant@127.0.0.1

# Cliente
ssh -p 2214 vagrant@127.0.0.1
```

---

## Verificación del sistema

### Estado esperado después de `vagrant up`:

**Master**:
- MySQL corriendo y escuchando en 0.0.0.0:3306
- Binlog habilitado con posición > 0
- Usuarios replicator creados para ambos slaves
- Bases de datos `test` y `sbtest` con datos iniciales

**Slaves**:
- MySQL corriendo con read_only=ON
- Replicación activa: `Slave_IO_Running: Yes` y `Slave_SQL_Running: Yes`
- `Seconds_Behind_Master: 0` o muy bajo
- Datos replicados desde el maestro presentes

**Balancer**:
- Nginx corriendo y escuchando en puertos 3307 y 3308
- Configuración válida (`nginx -t` sin errores)
- Upstreams definidos correctamente en `/etc/nginx/nginx.conf`

**Client**:
- mysql-client instalado
- sysbench instalado
- Puede conectarse al balanceador en ambos puertos
- Datos de sysbench preparados en `sbtest` (4 tablas con 10,000 registros cada una)

### Comandos de verificación rápida:

**Verificar replicación en slaves**:
```bash
# SSH a cada slave y ejecutar:
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master"
```

**Verificar Nginx**:
```bash
# SSH al balanceador:
sudo systemctl status nginx
sudo ss -tlpn | grep -E ':3307|:3308'
```

**Probar conectividad desde cliente**:
```bash
# SSH al cliente:
mysql -uroot -padmin -h 192.168.70.13 -P3307 -e "SELECT @@hostname;"
mysql -uroot -padmin -h 192.168.70.13 -P3308 -e "SELECT @@hostname;"
```

---

## Consideraciones técnicas

### Ventajas del diseño:

1. **Escalabilidad horizontal de lecturas**: Se pueden agregar más slaves para aumentar capacidad de lectura
2. **Separación de carga**: Las escrituras no compiten con las lecturas por recursos
3. **Simplicidad**: Nginx stream es ligero y fácil de configurar
4. **Replicación asíncrona**: Baja latencia en escrituras (el maestro no espera a los slaves)

### Limitaciones:

1. **No hay failover automático**: Si el maestro cae, se requiere intervención manual
2. **Replication lag**: Los slaves pueden estar ligeramente desactualizados (eventual consistency)
3. **Sin health checks activos**: Nginx no verifica proactivamente el estado de los backends
4. **Balanceo simple**: Round-robin no considera la carga real de cada nodo
5. **Sin read-after-write consistency**: Una lectura inmediata después de una escritura podría ir a un slave no actualizado

### Mejoras para producción:

- **ProxySQL**: Reemplazar Nginx por ProxySQL para query routing inteligente, health checks, y failover automático
- **MySQL Router**: Alternativa nativa de MySQL con funcionalidades similares
- **Orchestrator**: Para gestión automática de topología de replicación y failover
- **Replicación semi-síncrona**: Para mayor consistencia a costa de algo de latencia
- **Monitoring**: Prometheus + MySQL Exporter para métricas detalladas
- **Replicación GTID**: En lugar de posiciones de binlog para mayor robustez

---

## Troubleshooting

### Problema: Slave no replica (Slave_IO_Running: No o Slave_SQL_Running: No)

**Diagnóstico**:
```bash
# En el slave problemático:
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Last_IO_Error|Last_SQL_Error"
```

**Soluciones comunes**:

1. **Error de usuario de replicación**: verificar que existe `replicator@IP_SLAVE` en el maestro:
```bash
# En el maestro:
mysql -uroot -padmin -e "SELECT User, Host FROM mysql.user WHERE User='replicator';"
```

2. **Binlog/posición incorrectos**: reiniciar replicación desde el slave:
```bash
# En el slave:
MASTER_LOG_FILE=$(mysql -ureplicator -preplicator_pass -h 192.168.70.10 -e "SHOW MASTER STATUS\G" | grep File | awk '{print $2}')
MASTER_LOG_POS=$(mysql -ureplicator -preplicator_pass -h 192.168.70.10 -e "SHOW MASTER STATUS\G" | grep Position | awk '{print $2}')

mysql -uroot -padmin <<EOF
STOP SLAVE;
RESET SLAVE ALL;
CHANGE MASTER TO
    MASTER_HOST='192.168.70.10',
    MASTER_USER='replicator',
    MASTER_PASSWORD='replicator_pass',
    MASTER_LOG_FILE='$MASTER_LOG_FILE',
    MASTER_LOG_POS=$MASTER_LOG_POS;
START SLAVE;
EOF

mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running"
```

### Problema: No puedo conectar desde cliente al balanceador

**Causas comunes**:
- Nginx no está corriendo en el balanceador
- Firewall bloqueando puertos 3307/3308
- Error en configuración de Nginx

**Diagnóstico**:
```bash
# Desde el balanceador:
sudo systemctl status nginx
sudo ss -tlpn | grep -E ':3307|:3308'
sudo tail -n 100 /var/log/nginx/error.log
```

**Solución**:
```bash
# Reiniciar Nginx:
sudo systemctl restart nginx

# Si hay errores de configuración:
sudo cp /vagrant/config/conf.balancer /etc/nginx/nginx.conf
sudo nginx -t
sudo systemctl reload nginx
```

### Problema: Nginx no distribuye tráfico a todos los nodos

**Causa**: Configuración de upstream incorrecta o falta un servidor

**Verificar configuración**:
```bash
# En el balanceador:
grep -A 5 "upstream mysql_read" /etc/nginx/nginx.conf
```

Debe mostrar los 3 servidores:
- 192.168.70.10:3306 (maestro)
- 192.168.70.11:3306 (slave1)
- 192.168.70.12:3306 (slave2)

**Logs para debugging**:
```bash
# Verificar a qué backends se están enviando las conexiones:
sudo tail -f /var/log/nginx/error.log
```

---

## Referencias útiles

### Documentación MySQL:
- [MySQL Replication](https://dev.mysql.com/doc/refman/8.0/en/replication.html)
- [Binary Log](https://dev.mysql.com/doc/refman/8.0/en/binary-log.html)
- [SHOW SLAVE STATUS](https://dev.mysql.com/doc/refman/8.0/en/show-slave-status.html)

### Documentación Nginx:
- [Nginx Stream Module](http://nginx.org/en/docs/stream/ngx_stream_core_module.html)
- [Nginx Upstream](http://nginx.org/en/docs/stream/ngx_stream_upstream_module.html)

### Para pruebas detalladas:
Ver el archivo **DOCUMENTACION_COMPLETA.md** que incluye:
- 7 casos de prueba paso a paso
- Comandos sysbench completos
- Ejemplos de verificación de balanceo
- Simulación de fallos y recuperación

---

Fin del documento.
