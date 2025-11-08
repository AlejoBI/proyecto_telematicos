#!/bin/bash
# Script de provisioning para MySQL Master

# Configuración de red DNS
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null

echo "Instalando MySQL Server en el maestro..."

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y mysql-server

echo "Configurando MySQL como maestro..."
systemctl stop mysql
cp /vagrant/config/my.conf.master /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl start mysql

if systemctl is-active --quiet mysql; then
    echo "MySQL está corriendo como maestro."
else
    echo "MySQL no se pudo iniciar." >&2
    exit 1
fi

echo "Configurando usuario root local y creando usuarios de replicación..."
mysql -uroot <<EOF
-- Configurar contraseña para root local
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'admin';
FLUSH PRIVILEGES;
EOF

# Crear usuarios de replicación para ambos slaves
mysql -uroot -padmin <<EOF
-- Usuario de replicación para slave1 (192.168.70.11)
CREATE USER 'replicator'@'192.168.70.11' IDENTIFIED WITH mysql_native_password BY 'replicator_pass';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replicator'@'192.168.70.11';

-- Usuario de replicación para slave2 (192.168.70.12)
CREATE USER 'replicator'@'192.168.70.12' IDENTIFIED WITH mysql_native_password BY 'replicator_pass';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replicator'@'192.168.70.12';

FLUSH PRIVILEGES;
EOF

echo "Configurando acceso remoto desde balanceador y slaves..."
mysql -uroot -padmin <<EOF
-- Acceso desde balanceador (192.168.70.13)
CREATE USER 'root'@'192.168.70.13' IDENTIFIED BY 'admin';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'192.168.70.13' WITH GRANT OPTION;

-- Acceso desde slave1 (192.168.70.11)
CREATE USER 'root'@'192.168.70.11' IDENTIFIED BY 'admin';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'192.168.70.11' WITH GRANT OPTION;

-- Acceso desde slave2 (192.168.70.12)
CREATE USER 'root'@'192.168.70.12' IDENTIFIED BY 'admin';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'192.168.70.12' WITH GRANT OPTION;

FLUSH PRIVILEGES;
EOF

echo "Creando base de datos de prueba..."
mysql -uroot -padmin <<EOF
CREATE DATABASE IF NOT EXISTS test;
CREATE DATABASE IF NOT EXISTS sbtest;
USE test;
CREATE TABLE IF NOT EXISTS test (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO test (name) VALUES ('dato_inicial_1'), ('dato_inicial_2');
EOF

echo "Maestro configurado correctamente."
echo "IP del maestro: 192.168.70.10"
echo "Usuarios creados:"
echo "  - root@localhost (admin)"
echo "  - replicator@192.168.70.11 (para slave1)"
echo "  - replicator@192.168.70.12 (para slave2)"
echo "  - root@192.168.70.13 (acceso desde balanceador)"
