# Proyecto 3: Balanceo MySQL + Nginx — Documentación completa

## Glosario de Términos Técnicos

Para facilitar la explicación y comprensión del proyecto, aquí están los términos clave:

### Términos de Arquitectura:
- **Round-robin**: Algoritmo de balanceo que distribuye las peticiones de forma cíclica. Si hay 3 servidores (A, B, C), la primera petición va a A, la segunda a B, la tercera a C, la cuarta vuelve a A, y así sucesivamente. Es como repartir cartas en turnos.

- **Balanceo de carga**: Técnica para distribuir el trabajo entre varios servidores en lugar de saturar uno solo. Mejora rendimiento y evita que un servidor sea el cuello de botella.

- **Proxy TCP (capa 4)**: Un intermediario que reenvía conexiones de red sin interpretar el contenido. Nginx actúa como proxy: recibe conexiones del cliente y las redirige a los servidores MySQL sin leer las queries SQL.

- **Upstream**: En Nginx, es un grupo de servidores backend. Por ejemplo, "upstream mysql_read" agrupa los 3 nodos MySQL para lecturas.

### Términos de MySQL:

- **Master (Maestro)**: El servidor principal de base de datos que acepta escrituras (INSERT, UPDATE, DELETE). Es la "fuente de verdad" de los datos.

- **Slave (Esclavo/Réplica)**: Servidor de base de datos que copia los datos del maestro automáticamente. Solo acepta lecturas (SELECT) para evitar conflictos.

- **Replicación**: Proceso automático donde los slaves copian los cambios del master. Es como tener copias sincronizadas de un documento.

- **Binlog (Binary Log)**: Archivo donde MySQL registra todos los cambios (escrituras). Es el "diario" que los slaves leen para saber qué cambios aplicar.

- **Relay Log**: En el slave, es una copia temporal del binlog del master antes de aplicar los cambios. Es como una "bandeja de entrada" de cambios por procesar.

- **Replicación asíncrona**: Los slaves copian datos del master con un pequeño retraso (típicamente milisegundos). El master no espera a que los slaves confirmen, continúa trabajando.

- **Lag de replicación**: El tiempo de retraso entre que el master ejecuta un cambio y el slave lo aplica. Se mide con `Seconds_Behind_Master` (idealmente debe ser 0).

- **Read-only**: Configuración que previene que un servidor acepte escrituras directas. Los slaves están en read-only para mantener consistencia.

### Términos de Rendimiento:

- **TPS (Transactions Per Second)**: Transacciones por segundo. Mide cuántas operaciones completa la base de datos. Mayor = mejor rendimiento.

- **Throughput**: Cantidad de trabajo que el sistema puede procesar en un tiempo dado. Similar a TPS pero más general.

- **Latencia**: Tiempo que tarda una operación en completarse. Se mide en milisegundos (ms). Menor = mejor.

- **Percentil 95 (p95)**: El 95% de las operaciones son más rápidas que este valor. Es mejor indicador que el promedio porque ignora picos extremos.

- **Sysbench**: Herramienta de benchmarking que simula carga de usuarios concurrentes haciendo operaciones en la base de datos.

### Términos de Alta Disponibilidad:

- **Failover**: Proceso de cambiar automáticamente a un servidor de respaldo cuando el principal falla. En este proyecto es manual (limitación conocida).

- **Alta disponibilidad (HA)**: Capacidad del sistema de seguir funcionando incluso si un componente falla. Nuestro sistema tolera fallo de 1 slave.

- **Health check**: Verificación periódica de que un servidor está funcionando. Nginx detecta fallos cuando intenta conectar (no hace checks proactivos).

### Términos de Configuración:

- **server-id**: Identificador único de cada servidor MySQL en un clúster de replicación. Master=1, Slave1=2, Slave2=3.

- **bind-address**: Dirección IP en la que MySQL escucha conexiones. `0.0.0.0` significa "acepta desde cualquier IP".

- **Provisioning**: Proceso automatizado de instalar y configurar software en servidores. Vagrant ejecuta scripts de provisioning para configurar todo.

---

## Resumen de la arquitectura

### Máquinas virtuales (IPs y roles)
- **mysql_master** (192.168.70.10) — Servidor maestro MySQL. Maneja todas las **escrituras** y replica datos a los esclavos.
- **mysql_slave** (192.168.70.11) — Esclavo 1. Replica datos del maestro y atiende **lecturas**.
- **mysql_slave2** (192.168.70.12) — Esclavo 2. Replica datos del maestro y atiende **lecturas**.
- **nginx_balancer** (192.168.70.13) — Balanceador Nginx con módulo stream (TCP proxy):
  - Puerto 3307 - balanceo round-robin para **lecturas** entre maestro, slave1 y slave2.
  - Puerto 3308 - envía todas las **escrituras** al maestro.
- **client** (192.168.70.14) — VM cliente para ejecutar pruebas (mysql client, sysbench).

### Credenciales
- Usuario MySQL: `root`
- Contraseña: `admin`
- Usuario de replicación (maestro a esclavos): `replicator` / `replicator_pass`

### Puertos SSH (desde el host Windows)
- Maestro: `ssh -p 2210 vagrant@127.0.0.1`
- Slave1: `ssh -p 2211 vagrant@127.0.0.1`
- Slave2: `ssh -p 2212 vagrant@127.0.0.1`
- Balancer: `ssh -p 2213 vagrant@127.0.0.1`
- Client: `ssh -p 2214 vagrant@127.0.0.1`

---

## Beneficios de la arquitectura con 2 slaves

### 1. Mayor throughput de lectura
- Lecturas balanceadas entre maestro y 2 slaves (3 nodos totales).
- ~50% más capacidad de lecturas concurrentes comparado con un solo slave.

### 2. Alta disponibilidad
- Si un slave falla, el otro sigue atendiendo lecturas.
- Nginx automáticamente deja de enviar tráfico a un nodo caído.
- 2 candidatos disponibles para promover a maestro en caso de fallo del master.

### 3. Distribución de carga uniforme
- Round-robin entre 3 nodos reduce la carga individual en cada servidor.
- Mejora tiempos de respuesta bajo cargas altas.

### 4. Tolerancia a fallos
- Sistema puede perder 1 slave y seguir funcionando con capacidad reducida.
- Replicación continúa activa en el slave restante.

---

## Cómo levantar el entorno completo

Desde PowerShell en la carpeta del proyecto:

```powershell
# Levantar todas las VMs (maestro, slave1, slave2, balancer, client)
vagrant up
```

Espera a que termine el provisioning. Verifica que todas las VMs estén corriendo:

```powershell
vagrant status
```

---

## Verificaciones iniciales (ejecutar en cada VM)

### En mysql_master (SSH puerto 2210)
```bash
sudo systemctl status mysql
mysql -uroot -padmin -e "SHOW MASTER STATUS\G"
mysql -uroot -padmin -e "SELECT User, Host FROM mysql.user WHERE User='admin';"
```

### En mysql_slave (SSH puerto 2211)
```bash
sudo systemctl status mysql
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master"
```

### En mysql_slave2 (SSH puerto 2212)
```bash
sudo systemctl status mysql
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master"
```

**Qué buscar**:
- `Slave_IO_Running: Yes`
- `Slave_SQL_Running: Yes`
- `Seconds_Behind_Master: 0` (o valor bajo)

### En nginx_balancer (SSH puerto 2213)
```bash
sudo systemctl status nginx
sudo nginx -t
sudo ss -tlpn | grep -E ':3307|:3308'
```

**Qué buscar**:
- Nginx activo y escuchando en puertos 3307 (lecturas) y 3308 (escrituras).

---

## Casos de prueba detallados (paso a paso)

### PRUEBA 1: Verificar replicación a ambos slaves (vía balancer)

**Objetivo**: Confirmar que los datos escritos en el maestro se replican a slave1 y slave2, usando SOLO el balanceador.

**Dónde ejecutar**: VM `client` (SSH puerto 2214)

**Pasos**:

1. Insertar un registro con timestamp único (vía balancer puerto 3308 - escritura):
```bash
TIMESTAMP=$(date +%s)
mysql -uroot -padmin -h 192.168.70.13 -P3308 -e "INSERT INTO test.test (name) VALUES ('repl_test_$TIMESTAMP');"
echo "Insertado: repl_test_$TIMESTAMP"
```

2. Leer múltiples veces vía puerto 3307 (lecturas balanceadas entre los 3 nodos):
```bash
for i in {1..12}; do
  echo "--- Lectura $i ---"
  mysql -uroot -padmin -h 192.168.70.13 -P3307 -e "SELECT @@hostname AS servidor, name FROM test.test WHERE name LIKE 'repl_test_%' ORDER BY id DESC LIMIT 1;" 2>/dev/null
  sleep 0.5
done
```

**Resultado esperado**: 
- El dato insertado aparece en TODAS las lecturas (indicando que se replicó a ambos slaves).
- Verás `@@hostname` alternando entre `mysql-master`, `mysql-slave` y `mysql-slave2` (confirmando balanceo).

**Verificación directa del estado de replicación** (conectar SSH a cada slave):
- En slave1 (puerto SSH 2211):
```bash
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master"
```
- En slave2 (puerto SSH 2212):
```bash
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master"
```

**Qué hacer si falla**: 
- Verificar `SHOW SLAVE STATUS\G` en cada slave (buscar errores en `Last_IO_Error` o `Last_SQL_Error`).
- Revisar logs: `sudo tail -n 200 /var/log/mysql/error.log` en el slave problemático.

---

### PRUEBA 2: Verificar balanceo de lecturas entre los 3 nodos

**Objetivo**: Confirmar que Nginx distribuye lecturas entre maestro, slave1 y slave2.

**Dónde ejecutar**: VM `client`

**Pasos**:

1. Leer múltiples veces vía puerto 3307 (lecturas):
```bash
for i in {1..12}; do
  mysql -uroot -padmin -h 192.168.70.13 -P3307 -e "SELECT @@hostname, NOW();" 2>/dev/null
  sleep 0.5
done
```

2. Ver logs de nginx para confirmar upstreams usados:
```bash
# Ejecutar en nginx_balancer (SSH puerto 2213)
sudo tail -n 50 /var/log/nginx/mysql_access.log | grep "192.168.70"
```

**Resultado esperado**: 
- Verás conexiones distribuidas a `192.168.70.10:3306`, `192.168.70.11:3306` y `192.168.70.12:3306`.
- La distribución debería ser aproximadamente uniforme (round-robin).

**Interpretación**: Si ves los 3 upstreams en los logs, el balanceo está funcionando correctamente.

---

### PRUEBA 3: Prueba de carga con Sysbench (lectura+escritura)

**Objetivo**: Medir throughput (TPS) y latencia bajo carga con el nuevo slave agregado.

**Dónde ejecutar**: VM `client`

**Preparar datos** (si no están listos):
```bash
sysbench /usr/share/sysbench/oltp_read_write.lua \
  --mysql-host=192.168.70.13 \
  --mysql-port=3308 \
  --mysql-user=root \
  --mysql-password=admin \
  --mysql-db=sbtest \
  --tables=4 \
  --table-size=10000 \
  prepare
```

**Ejecutar prueba mixta (70% lecturas, 30% escrituras)**:
```bash
sysbench /usr/share/sysbench/oltp_read_write.lua \
  --mysql-host=192.168.70.13 \
  --mysql-port=3308 \
  --mysql-user=root \
  --mysql-password=admin \
  --mysql-db=sbtest \
  --tables=4 \
  --table-size=10000 \
  --threads=16 \
  --time=60 \
  --report-interval=10 \
  run
```

**Métricas importantes**:
- **transactions** (total de transacciones completadas).
- **transactions/sec (TPS)** — throughput (mayor es mejor).
- **avg latency** — latencia promedio en ms (menor es mejor).
- **95th percentile latency** — latencia p95 (estabilidad).
- **errors** — deben ser 0.

**Métricas esperadas**:
- TPS alto gracias a la distribución de lecturas entre 3 nodos.
- Latencia de lectura estable (baja variabilidad en p95/p99).

**Comparación (opcional)**: Apagar un slave (`sudo systemctl stop mysql`) y volver a correr sysbench. Deberías ver:
- TPS reducido (especialmente bajo alta concurrencia).
- Latencias de lectura incrementadas (más carga en los nodos restantes).

---

### PRUEBA 4: Prueba de carga solo lecturas (evaluar capacidad de throughput)

**Objetivo**: Medir capacidad de lecturas con los 3 nodos disponibles.

**Dónde ejecutar**: VM `client`

**Ejecutar con slave2 activo**:
```bash
sysbench /usr/share/sysbench/oltp_read_only.lua \
  --mysql-host=192.168.70.13 \
  --mysql-port=3307 \
  --mysql-user=root \
  --mysql-password=admin \
  --mysql-db=sbtest \
  --threads=24 \
  --time=60 \
  --report-interval=10 \
  run
```

**Anotar**: TPS, latencia promedio, p95.

**Ejecutar con un slave apagado** (simular fallo):
```bash
# Primero apagar un slave (ejemplo: slave2, en SSH puerto 2212):
sudo systemctl stop mysql

# Volver a ejecutar sysbench (mismo comando de arriba)
```

**Comparar resultados**:
- TPS con 3 nodos debería ser ~33-50% mayor que con 2 nodos.
- Latencia con 3 nodos debería ser menor.

**Tabla de ejemplo** (valores ilustrativos):

| Configuración | TPS (aprox) | Latencia avg (ms) | Latencia p95 (ms) |
|---------------|-------------|-------------------|-------------------|
| 3 nodos (maestro + 2 slaves) | 3000-4000 | 6-8 | 12-15 |
| 2 nodos (maestro + 1 slave) | 2000-2700 | 9-12 | 18-25 |

---

### PRUEBA 5: Simular fallo de un slave y verificar continuidad

**Objetivo**: Demostrar alta disponibilidad (sistema sigue funcionando si un slave cae).

**Pasos**:

1. **Ejecutar carga de fondo** (en VM `client`):
```bash
sysbench /usr/share/sysbench/oltp_read_only.lua \
  --mysql-host=192.168.70.13 \
  --mysql-port=3307 \
  --mysql-user=root \
  --mysql-password=admin \
  --mysql-db=sbtest \
  --threads=8 \
  --time=120 \
  --report-interval=10 \
  run &
```

2. **Mientras corre sysbench, apagar slave1** (SSH a slave1, puerto 2211):
```bash
sudo systemctl stop mysql
```

3. **Observar salida de sysbench**: 
   - Verás incremento temporal en latencia (mientras nginx detecta el fallo).
   - Luego el sistema se estabiliza (nginx deja de enviar tráfico a slave1).
   - Las lecturas se balancean entre maestro y slave2 únicamente.

4. **Verificar logs de nginx** (en balancer):
```bash
sudo tail -f /var/log/nginx/error.log
```
Buscar mensajes tipo: `connect() failed (111: Connection refused) ... upstream: "192.168.70.11:3306"`

5. **Levantar slave1 de nuevo**:
```bash
sudo systemctl start mysql
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running"
```

**Resultado esperado**:
- Sistema tolera la caída de 1 slave sin interrumpir el servicio (solo reduce capacidad).
- Cuando el slave vuelve, nginx automáticamente lo incluye en el balanceo.

---

### PRUEBA 6: Consultas SQL para verificar distribución de carga

**Objetivo**: Usar variables de MySQL para confirmar a qué servidor se conectó cada query.

**Dónde ejecutar**: VM `client`

**Query para ver hostname del servidor**:
```bash
mysql -uroot -padmin -h 192.168.70.13 -P3307 -e "SELECT @@hostname AS servidor, NOW() AS timestamp;"
```

**Ejecutar 20 veces y contar distribución**:
```bash
for i in {1..20}; do
  mysql -uroot -padmin -h 192.168.70.13 -P3307 -e "SELECT @@hostname;" 2>/dev/null | grep -v "@@hostname"
done | sort | uniq -c
```

**Resultado esperado** (ejemplo):
```
   7 mysql-master
   7 mysql-slave
   6 mysql-slave2
```

Distribución aproximadamente equitativa entre los 3 nodos.

---

### PRUEBA 7: Lag de replicación bajo carga de escritura

**Objetivo**: Verificar que los slaves se mantienen sincronizados bajo escrituras intensivas.

**Pasos**:

1. **Ejecutar carga de escritura** (en VM `client`):
```bash
sysbench /usr/share/sysbench/oltp_write_only.lua \
  --mysql-host=192.168.70.13 \
  --mysql-port=3308 \
  --mysql-user=root \
  --mysql-password=admin \
  --mysql-db=sbtest \
  --threads=8 \
  --time=60 \
  run
```

2. **Mientras corre, monitorear lag en ambos slaves** (ejecutar en SSH a cada slave):

En slave1:
```bash
watch -n 2 "mysql -uroot -padmin -e \"SHOW SLAVE STATUS\G\" | grep Seconds_Behind_Master"
```

En slave2:
```bash
watch -n 2 "mysql -uroot -padmin -e \"SHOW SLAVE STATUS\G\" | grep Seconds_Behind_Master"
```

**Qué buscar**:
- `Seconds_Behind_Master: 0` (ideal).
- Valores bajos (<5 segundos) son aceptables en laboratorio.
- Si el lag crece constantemente, indica que el slave no puede procesar binlogs al ritmo del maestro (bottleneck de I/O o CPU).

---

## Resumen de comandos por máquina (cheatsheet)

### En `client` (192.168.70.14 / SSH 2214):

**TODAS las operaciones de datos pasan por el balanceador (nginx)**:

```bash
# Lectura vía balancer (puerto 3307 - balanceado entre maestro y 2 slaves)
mysql -uroot -padmin -h 192.168.70.13 -P3307 -e "SELECT COUNT(*) FROM test.test;"
mysql -uroot -padmin -h 192.168.70.13 -P3307 -e "SELECT * FROM test.test ORDER BY id DESC LIMIT 10;"

# Escritura vía balancer (puerto 3308 - solo maestro)
mysql -uroot -padmin -h 192.168.70.13 -P3308 -e "INSERT INTO test.test (name) VALUES ('test_$(date +%s)');"

# Sesión interactiva (para múltiples queries)
mysql -uroot -padmin -h 192.168.70.13 -P3308
# Dentro del prompt MySQL:
# USE test;
# INSERT INTO test (name) VALUES ('dato1'), ('dato2');
# SELECT * FROM test ORDER BY id DESC LIMIT 5;
# exit

# Verificar distribución de balanceo (ver qué servidor atiende cada query)
for i in {1..15}; do
  mysql -uroot -padmin -h 192.168.70.13 -P3307 -e "SELECT @@hostname, NOW();" 2>/dev/null | tail -n 1
done

# Sysbench prepare
sysbench /usr/share/sysbench/oltp_read_write.lua --mysql-host=192.168.70.13 --mysql-port=3308 --mysql-user=root --mysql-password=admin --mysql-db=sbtest --tables=4 --table-size=10000 prepare

# Sysbench run (read+write)
sysbench /usr/share/sysbench/oltp_read_write.lua --mysql-host=192.168.70.13 --mysql-port=3308 --mysql-user=root --mysql-password=admin --mysql-db=sbtest --threads=16 --time=60 run

# Sysbench run (read only) - usa puerto 3307 para lecturas balanceadas
sysbench /usr/share/sysbench/oltp_read_only.lua --mysql-host=192.168.70.13 --mysql-port=3307 --mysql-user=root --mysql-password=admin --mysql-db=sbtest --threads=16 --time=60 run
```

### En `mysql_master` (192.168.70.10 / SSH 2210):
```bash
# Ver estado del maestro
mysql -uroot -padmin -e "SHOW MASTER STATUS\G"

# Ver conexiones activas
mysql -uroot -padmin -e "SHOW PROCESSLIST;"

# Simular fallo
sudo systemctl stop mysql
# Recuperar
sudo systemctl start mysql
```

### En `mysql_slave` / `mysql_slave2` (SSH 2211 / 2212):

**SOLO para verificar estado de replicación (no para operaciones de datos)**:

```bash
# Ver estado de replicación (ejecutar dentro de cada slave via SSH)
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G"

# Ver lag específico
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep Seconds_Behind_Master

# Ver últimos datos replicados (verificación local, no desde client)
mysql -uroot -padmin -e "SELECT * FROM test.test ORDER BY id DESC LIMIT 5;"

# Simular fallo
sudo systemctl stop mysql
# Recuperar
sudo systemctl start mysql

# Verificar replicación después de recuperar
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running"
```

**Nota importante**: Para la sustentación, TODAS las consultas de datos desde `client` deben pasar por el balanceador (192.168.70.13). El acceso directo a slaves es SOLO para verificar estado de replicación con `SHOW SLAVE STATUS`.

### En `nginx_balancer` (192.168.70.13 / SSH 2213):
```bash
# Verificar estado
sudo systemctl status nginx
sudo nginx -t

# Ver logs de balanceo
sudo tail -f /var/log/nginx/mysql_access.log
sudo tail -f /var/log/nginx/error.log

# Recargar config (si cambias conf.balancer)
sudo systemctl reload nginx
```

---

## Qué explicar en la presentación

1. **Arquitectura**: Dibuja el diagrama (1 maestro, 2 slaves, 1 balancer, 1 client). Explica flujo de escritura (→ maestro) y lectura (round-robin entre 3 nodos).

2. **Beneficios de la arquitectura**:
   - Mayor capacidad de lecturas distribuidas entre 3 nodos.
   - Alta disponibilidad (tolera caída de 1 slave).
   - Menor latencia bajo carga alta.

3. **Replicación maestro-esclavo**: Explica binlog, relay log, `CHANGE MASTER TO`, y cómo los esclavos se mantienen sincronizados.

4. **Balanceo con Nginx stream**: Explica que nginx hace TCP proxy (capa 4), no interpreta SQL. Round-robin simple. Puerto 3307 (reads) vs 3308 (writes).

5. **Pruebas realizadas**:
   - Replicación funcional (SHOW SLAVE STATUS).
   - Balanceo verificado (logs de nginx muestran distribución).
   - Carga con sysbench: TPS, latencia, comparación con/sin slave2.
   - Tolerancia a fallos: apagar un slave y mostrar que el sistema sigue.

6. **Limitaciones y mejoras futuras**:
   - Fallo del maestro requiere intervención manual (no hay auto-failover).
   - Nginx no hace health checks activos (solo detecta fallo al intentar conectar).
   - Para producción: usar ProxySQL (read/write split automático, health checks, failover) o MySQL Router.

---

## Troubleshooting común

### Problema: Un slave no replica (Slave_IO_Running: No)
**Diagnóstico**:
```bash
mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep Last_IO_Error
```
**Soluciones**:
- Usuario de replicación no existe o no tiene permisos: ejecutar en maestro (ajustar IP del slave):
  ```bash
  mysql -uroot -padmin -e "CREATE USER IF NOT EXISTS 'replicator'@'192.168.70.XX' IDENTIFIED BY 'replicator_pass'; GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'192.168.70.XX'; FLUSH PRIVILEGES;"
  ```
- Binlog/posición incorrectos: volver a hacer `CHANGE MASTER TO` con valores actuales.

### Problema: Nginx no balancea a un slave
**Diagnóstico**:
```bash
sudo tail -n 100 /var/log/nginx/mysql_access.log | grep "192.168.70"
```
Si falta un slave, revisar:
```bash
sudo nginx -t
sudo systemctl reload nginx
```
Confirmar que `conf.balancer` tiene las líneas de todos los servers.

### Problema: Lag alto en un slave (Seconds_Behind_Master > 10)
**Causas comunes**:
- Carga muy alta de escritura en el maestro.
- Slave con recursos limitados (CPU/IO).
- Queries lentas en el slave.

**Solución temporal**: reducir carga de escritura o aumentar recursos de la VM del slave.

---

Fin del documento. Todo listo para sustentación.
