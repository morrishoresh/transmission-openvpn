#!/bin/sh

while :
do
	sleep 60
	IP=$(/checkip.sh)
	if test -z "$IP"
	then
		TPID=$(ps -ef | grep openvpn | grep transmission | awk '{print $2'})
		kill $TPID
	fi
done
