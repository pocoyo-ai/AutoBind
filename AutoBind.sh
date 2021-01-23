#!/bin/bash

# Interfaz

tput setaf 39;
echo ''
echo ' # ¡ Este script reemplazará toda tu configuración Netplan y DNS ! '
echo ' # Recuerda ejecutar el script con sudo '
echo ' # Puedes cancelar en cualquier momento con CTRL + C '
echo ''
tput sgr 0

tput setaf 73;
read -p "¿Qué ip utilizarás como servidor? (ej: 192.168.13.201): " var_ip
read -p "¿Qué interfaz es adaptador puente? (ej: enp0s3): " var_int
read -p "¿Qué dominio utilizará tu servidor dns? (ej: hackers.es): " var_domain
tput sgr 0

# Cálculos para ip inversa y gateway

IpR1=$(echo $var_ip | cut -d '.' -f1)
IpR2=$(echo $var_ip | cut -d '.' -f2)
IpR3=$(echo $var_ip | cut -d '.' -f3)
IpRev="$IpR3.$IpR2.$IpR1"

var_gateway="$IpR1.$IpR2.$IpR3.1"

# Valores que se utilizarán luego

NetplanTemplate="network:
  ethernets:
   $var_int:
    addresses: [$var_ip/24]
    gateway4: $var_gateway
    nameservers:
     search: [$var_domain]
     addresses: [$var_ip, 8.8.8.8]
  version: 2"

DNSdir=/etc/bind

DnsZones="//Zona directa
zone "'"'"$var_domain"'"'" {
	type master;
	file "'"'"$DNSdir/db.$var_domain.direct"'"'";
	notify yes;
};
//Zona inversa
zone "'"'"$IpRev.in-addr.arpa"'"'" {
	type master;
	file "'"'"$DNSdir/db.$IpRev.rev"'"'";
	notify yes;
};"

# Modificando netplan

if [ -e /etc/netplan/01-network-manager-all.yaml ]; then
	cp /etc/netplan/01-network-manager-all.yaml /etc/netplan/01-network-manager-all.yaml.original
	echo "Se ha realizado una copia de seguridad del fichero 01-network-manager-all.yaml.original"
	sleep 1
	rm /etc/netplan/01-network-manager-all.yaml
	sudo echo "$NetplanTemplate" > /etc/netplan/01-network-manager-all.yaml
	sleep 1
	sudo netplan apply
	echo "Se han aplicado los cambios Netplan"
else
	echo 'Ha ocurrido un error al encontrar el fichero 01-network-manager-all.yaml, prueba a crearlo con touch /etc/netplan/01-network-manager-all.yaml'
fi
	
# Instalando dependencias

echo 'Se instalarán las dependencias bind9 y dns-utils'

sudo dpkg -s ifupdown &> /dev/null

if [ -d /usr/share/doc/ifupdown/ ];
then
	tput setaf 2; echo "El paquete ifupdown está instalado."
	tput sgr 0
else
	tput setaf 1; echo "Se instalará el paquete ifupdown."
	sleep 5s
	tput setaf 3;
	sudo apt-get -y install ifupdown
	tput sgr 0
fi

sudo dpkg -s bind9 &> /dev/null

if [ $? -ne 0 ]
then
	tput setaf 3;echo "Bind9 no se encuentra instalado, instalando..."
	sudo apt-get -y update
	sudo apt-get -y install bind9
	tput sgr 0;
else
	tput setaf 1;
	sudo apt-get -y purge bind9
	tput setaf 2;echo "Reinstalando bind9."
	sudo apt-get -y install bind9
	tput sgr 0;
fi

sudo dpkg -s dnsutils &> /dev/null

if [ $? -ne 0 ]
then
	tput setaf 3;echo "Dnsutils no se encuentra instalado, instalando..."
	sudo apt-get -y install dnsutils
	tput sgr 0;
else
	tput setaf 1;
	sudo apt-get -y purge dnsutils
	tput setaf 2;echo "Reinstalando dnsutils."
	sudo apt-get -y install dnsutils
	tput sgr 0;
fi

# Configurando fichero named.conf.local

echo 'Realizando copia del fichero named.conf.local en el directorio /etc/bind/named.conf.local.original'
cp /etc/bind/named.conf.local /etc/bind/named.conf.local.original

# Creando zona directa e inversa

echo 'Generando bases de datos DNS.'

cp $DNSdir/db.local $DNSdir/db."$var_domain".direct
tput setaf 2;echo 'Zona directa creada.'
tput sgr 0;

cp $DNSdir/db.127 $DNSdir/db."$IpRev".rev
tput setaf 2;echo 'Zona inversa creada.'
tput sgr 0;

# Añadiendo configuración a zona directa e inversa

echo 'Creando zona directa e inversa...'

DnsZonesOut=$DnsZones

sudo sed -i '/rfc1918/G' $DNSdir/named.conf.local;
sudo echo "$DnsZonesOut" >> $DNSdir/named.conf.local
tput setaf 2;echo 'Se han añadido las zonas.'
tput sgr 0;

# Añadiendo zona alternativa

echo 'Copiando fichero named.conf.options'
echo 'Añadiendo un servidor DNS alternativo'
sed -i.bak '13s/.*/         forwarders {/g' $DNSdir/named.conf.options;
sed -i.bak '14s/.*/              8.8.8.8;/g' $DNSdir/named.conf.options;
sed -i.bak '15s/.*/         };/g' $DNSdir/named.conf.options;

# Configurando zona directa

echo 'Configurando zona directa'
read -e -i "s" -p '¿Incluir subdominios por defecto (s/n): ' DSubdomains

if [ $DSubdomains == s ];
then
	echo "Remplazando dominio local por $var_domain"
	sudo sed -i "s/localhost/$var_domain/g" $DNSdir/db.$var_domain.direct;
	sudo sed -i "s/127.0.0.1/$var_ip/g" $DNSdir/db.$var_domain.direct;
	echo "Añadiendo subdominios a zona directa."
	sudo sed -i '$a'"$var_domain.\	\IN	\A	$var_ip" $DNSdir/db.$var_domain.direct;
	sudo sed -i '$a'"dns.$var_domain.\	\IN	\A	$var_ip" $DNSdir/db.$var_domain.direct;
else
	echo 'Se continuará sin añadir dominios a la zona directa.'
fi

# Configurando zona inversa

HostIP=$(echo $var_ip | cut -d '.' -f4)

echo 'Configurando zona inversa'
read -e -i "s" -p '¿Incluir subdominios por defecto (s/n): ' ISubdomains

if [ $ISubdomains == s ];
then
	echo "Remplazando dominio local por $var_ip"
	sudo sed -i "s/localhost/$var_domain/g" $DNSdir/db.$IpRev.rev;
	sudo sed -i "s/1.0.0/$HostIP/g" $DNSdir/db.$IpRev.rev;
	echo "Añadiendo subdominios a zona inversa."
	sudo sed -i '$a'"$HostIP\	\IN	\PTR	dns.$var_domain." $DNSdir/db.$IpRev.rev;
else
	echo 'Se continuará sin añadir dominios a la zona directa.'
fi

tput setaf 3; echo 'Verificando configuración directa.'
tput sgr 0;
named-checkzone $var_domain $DNSdir/db.$var_domain.direct

tput setaf 3; echo 'Verificando configuración inversa.'
tput sgr 0;
named-checkzone $IpRev.in-addr.arpa $DNSdir/db.$IpRev.rev

sleep 1

# Reemplazando servidor en /etc/resolv.conf
# Via opcional de resolv.conf
# sudo sed -i s/nameserver 127.0.0.53/c \# nameserver 127.0.0.53/g" $ResolvDir;
# sudo sed -i s/options edns0/c \# options edns0/g" $ResolvDir;

ResolvDir=/etc/resolv.conf
DnsNMDir=/etc/NetworkManager

ResolvDef="domain $var_domain
search $var_domain
nameserver $var_ip"

sudo rm -r $ResolvDir
sudo touch $ResolvDir
sleep 1

tput setaf 6; echo "Reemplazando servidor en $ResolvDir"
tput sgr 0;

	sudo echo "$ResolvDef" >> $ResolvDir
	tput setaf 2; echo "El fichero ha sido reemplazado."
	tput sgr 0;

tput setaf 6; echo "Desactivando la actualización automática dns de Network-Manager."
tput sgr 0;

	DNScat=$(cat $DnsNMDir/NetworkManager.conf | grep -i 'dns=')

	if [ "$DNScat" == "" ];
	then
        sudo sed -i '/keyfile/a\dns=none' $DnsNMDir/NetworkManager.conf;
	else
        sudo sed -i 's/dns=true/dns=none/g' $DnsNMDir/NetworkManager.conf;
	fi

	echo "Permitiendo manejo de interfaces para Network-Manager"
	sudo sed -i "s/managed=none/managed=true/g" $DnsNMDir/NetworkManager.conf;
	
# Estableciendo ipv4 como protocolo dominante

if [ -e /etc/default/named ]; then
echo 'Se ha realizado una copia del fichero /etc/default/named'
sed -i.bak '6s/.*/OPTIONS="-4"/g' /etc/default/named;
echo 'Se ha establecido el protocolo ipv4 para el servidor dns'
else
echo 'No se encuentra el fichero named, debes activar el protocolo ipv4 para el servidor bind'
fi

# Reiniciando servicios y limpiando caché

tput setaf 2; echo "Reiniciando servicios y limpiando caché dns"
tput sgr 0;

	sudo systemd-resolve --flush-caches
	service named restart
	sudo service bind9 restart
	sudo service network-manager restart
	sleep 1

	tput setaf 2; host $var_ip
	tput sgr 0;
