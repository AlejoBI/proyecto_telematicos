#!/bin/bash
# Script de provisioning para Cliente (VM de pruebas)

# Configuración de red DNS
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null

echo "Instalando herramientas de prueba (mysql-client, sysbench)..."

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y default-mysql-client sysbench

echo "Esperando a que el balanceador esté disponible..."
sleep 15

echo "Preparando datos de prueba para sysbench..."
sysbench /usr/share/sysbench/oltp_read_write.lua \
--mysql-host=192.168.70.13 \
--mysql-port=3308 \
--mysql-user=root \
--mysql-password=admin \
--mysql-db=sbtest \
--tables=4 \
--table-size=10000 \
prepare

if [ $? -eq 0 ]; then
    echo "Cliente configurado correctamente. Datos de prueba preparados."
else
    echo "Cliente configurado, pero no se pudieron preparar datos de prueba."
    echo "Puedes ejecutar manualmente: sysbench ... prepare"
fi

echo "IP del cliente: 192.168.70.14"
echo "Conectar al balanceador:"
echo "  - Lecturas:   mysql -uroot -padmin -h 192.168.70.13 -P3307"
echo "  - Escrituras: mysql -uroot -padmin -h 192.168.70.13 -P3308"
