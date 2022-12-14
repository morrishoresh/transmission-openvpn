#!/bin/sh

while :
do
	sleep 60
	IP=$(/checkip.sh)
	if test -z "$IP"
	then
		# When this happens it is usually an indication that there is a problem with the VPN
		# connection. In this case we stop the vpn which will cause the init.sh script to
		# recreate a vpn session
		TPID=$(ps -ef | grep openvpn | grep transmission | awk '{print $2}')
		kill $TPID
	fi
done
