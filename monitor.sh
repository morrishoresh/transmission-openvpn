#!/bin/sh

# VPN type to monitor (openvpn|wireguard); defaults to openvpn for backward compat
VPN_TYPE=$1
if test -z "$VPN_TYPE"
then
	VPN_TYPE=openvpn
fi

while :
do
	sleep 60
	IP=$(/checkip.sh)
	if test -z "$IP"
	then
		# When this happens it is usually an indication that there is a problem with the VPN
		# connection. In this case we drop the VPN, which causes init.sh to recreate the session.
		if test "$VPN_TYPE" = "wireguard"
		then
			# wg-quick has no long-running process to kill; killing the daemon
			# breaks init.sh's foreground wait so it tears the tunnel down and re-ups it
			pkill transmission
		else
			TPID=$(ps -ef | grep openvpn | grep transmission | awk '{print $2}')
			kill $TPID
		fi
	fi
done
