#!/bin/sh

if test $(id -u) -ne 0
then
	echo "You must run this as root"
	exit 1
fi

if test -n "$DNS1$DNS2$DNS3"
then
	echo have dns
	echo -n "" > /etc/resolv.conf

	for DNS in $DNS1 $DNS2 $DNS3
	do
		if test -n "$DNS"
		then
			echo nameserver $DNS >> /etc/resolv.conf
		fi
done
fi

if test $(id -u transmission) -ne $XUID
then
	echo changing uid
	usermod -o -u "$XUID" transmission
fi

if test $(id -g transmission) -ne $XGID
then
	echo changing gid
	groupmod -g "$XGID" transmission
fi

if test  "$(getent passwd transmission | cut -d: -f6)" != "/home/transmission"
then
	echo changing home dir
	usermod -d /home/transmission transmission
fi

cd /etc/openvpn

while :
do
	openvpn --config default.vpn.ovpn --up "/usr/bin/su -l transmission -c transmission-daemon" --script-security 2
	sleep 3
done
