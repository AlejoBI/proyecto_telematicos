#!/bin/bash
# Script de provisioning para MySQL Slave 2

# Configuración de red DNS
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null

echo "Instalando MySQL Server en el esclavo 2..."

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y mysql-server

echo "Configurando MySQL como esclavo 2..."
systemctl stop mysql
cp /vagrant/config/my.conf.slave2 /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl start mysql

if systemctl is-active --quiet mysql; then
    echo "MySQL está corriendo como esclavo 2."
else
    echo "MySQL no se pudo iniciar." >&2
    exit 1
fi

echo "Configurando usuario root local..."
mysql -uroot <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'admin';
FLUSH PRIVILEGES;
EOF

echo "Obteniendo binlog y posición desde el maestro (192.168.70.10)..."
# Esperar a que el maestro esté disponible
sleep 10

# Conexión remota al maestro para obtener el log bin y la posición
read -r MASTER_LOG_FILE MASTER_LOG_POS <<< $(mysql -ureplicator -preplicator_pass -h 192.168.70.10 -e "SHOW MASTER STATUS\G" | awk '/File:/ {print $2} /Position:/ {print $2}' | tr '\n' ' ')

if [[ -z "$MASTER_LOG_FILE" || -z "$MASTER_LOG_POS" ]]; then
    echo "No se pudo obtener log binario y posición del maestro." >&2
    exit 1
fi

echo "MASTER_LOG_FILE = $MASTER_LOG_FILE"
echo "MASTER_LOG_POS  = $MASTER_LOG_POS"

echo "Configurando esclavo 2 para replicar desde el maestro..."
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

echo "Verificando estado de la replicación..."
sleep 3

SLAVE_IO_RUNNING=$(mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep "Slave_IO_Running:" | awk '{print $2}')
SLAVE_SQL_RUNNING=$(mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep "Slave_SQL_Running:" | awk '{print $2}')

if [[ "$SLAVE_IO_RUNNING" == "Yes" && "$SLAVE_SQL_RUNNING" == "Yes" ]]; then
    echo "La replicación está funcionando correctamente en esclavo 2."
else
    echo "La replicación NO está funcionando. Verifica configuración y logs." >&2
    mysql -uroot -padmin -e "SHOW SLAVE STATUS\G" | grep -E "Last_IO_Error|Last_SQL_Error"
    exit 1
fi

echo "Configurando acceso remoto desde balanceador y cliente..."
mysql -uroot -padmin <<EOF
-- Acceso desde balanceador (192.168.70.13)
CREATE USER 'root'@'192.168.70.13' IDENTIFIED BY 'admin';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'192.168.70.13' WITH GRANT OPTION;

-- Acceso desde cliente (192.168.70.14) - solo para verificar SHOW SLAVE STATUS
CREATE USER 'root'@'192.168.70.14' IDENTIFIED BY 'admin';
GRANT REPLICATION CLIENT ON *.* TO 'root'@'192.168.70.14';

FLUSH PRIVILEGES;
EOF

echo "Esclavo 2 configurado correctamente."
echo "IP del esclavo 2: 192.168.70.12"
echo "Replicando desde: 192.168.70.10 (maestro)"
