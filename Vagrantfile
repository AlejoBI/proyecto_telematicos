Vagrant.configure("2") do |config|

  # Maestro MySQL - maneja todas las escrituras y replica a slaves
  config.vm.define :mysql_master do |mysql_master|
    mysql_master.vm.box = "bento/ubuntu-22.04"
    mysql_master.vm.network :private_network, ip: "192.168.70.10"
    mysql_master.vm.hostname = "mysql-master"
    mysql_master.vm.provision "shell", path: "provision/master.sh"
    mysql_master.vm.network "forwarded_port", guest: 22, host: 2210, id: "ssh"
    mysql_master.vm.boot_timeout = 600
  end

  # Esclavo 1 - replica del maestro, atiende lecturas
  config.vm.define :mysql_slave do |mysql_slave|
    mysql_slave.vm.box = "bento/ubuntu-22.04"
    mysql_slave.vm.network :private_network, ip: "192.168.70.11"
    mysql_slave.vm.hostname = "mysql-slave"
    mysql_slave.vm.provision "shell", path: "provision/slave.sh"
    mysql_slave.vm.network "forwarded_port", guest: 22, host: 2211, id: "ssh"
    mysql_slave.vm.boot_timeout = 1600
  end

  # Esclavo 2 - replica del maestro, atiende lecturas
  config.vm.define :mysql_slave2 do |mysql_slave2|
    mysql_slave2.vm.box = "bento/ubuntu-22.04"
    mysql_slave2.vm.network :private_network, ip: "192.168.70.12"
    mysql_slave2.vm.hostname = "mysql-slave2"
    mysql_slave2.vm.provision "shell", path: "provision/slave2.sh"
    mysql_slave2.vm.network "forwarded_port", guest: 22, host: 2212, id: "ssh"
    mysql_slave2.vm.boot_timeout = 1600
  end

  # Balanceador Nginx - proxy TCP para lecturas (3307) y escrituras (3308)
  config.vm.define :nginx_balancer do |nginx_balancer|
    nginx_balancer.vm.box = "bento/ubuntu-22.04"
    nginx_balancer.vm.network :private_network, ip: "192.168.70.13"
    nginx_balancer.vm.hostname = "nginx-balancer"
    nginx_balancer.vm.provision "shell", path: "provision/balancer.sh"
    nginx_balancer.vm.network "forwarded_port", guest: 22, host: 2213, id: "ssh"
    nginx_balancer.vm.boot_timeout = 600
  end

  # Cliente - VM para ejecutar pruebas (mysql client, sysbench)
  config.vm.define :client do |client|
    client.vm.box = "bento/ubuntu-22.04"
    client.vm.network :private_network, ip: "192.168.70.14"
    client.vm.hostname = "client"
    client.vm.provision "shell", path: "provision/client.sh"
    client.vm.network "forwarded_port", guest: 22, host: 2214, id: "ssh"
    client.vm.boot_timeout = 600
  end

end