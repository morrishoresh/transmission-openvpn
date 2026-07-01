#!/bin/sh

# Usage: ./exec.sh [-s [seconds]] [--ip ADDR] [--dns1 DNS] [--dns2 DNS] [--dns3 DNS] [--no-vpn] [transmission-user]

if  test -n "$(docker ps -q -f name=transmission)"
then
	echo transmission is already running
	exit 1
fi

IP_ADDR=172.18.0.2
DNS1=1.1.1.1
DNS2=84.200.70.40
DNS3=1.0.0.1
NO_VPN_FLAG=""

while test $# -gt 0
do
	case "$1" in
	-s)
		shift
		case "$1" in
		''|*[!0-9]*) ;;
		*) sleep "$1"; shift ;;
		esac
		;;
	--ip)
		IP_ADDR=$2
		shift 2
		;;
	--dns1)
		DNS1=$2
		shift 2
		;;
	--dns2)
		DNS2=$2
		shift 2
		;;
	--dns3)
		DNS3=$2
		shift 2
		;;
	--no-vpn)
		NO_VPN_FLAG="--no-vpn"
		shift
		;;
	*)
		break
		;;
	esac
done

if test -n "$1"
then
	TRANSMISSION_USER=$1
else
	TRANSMISSION_USER=transmission
fi

TRANSMISSION_HOME_DIR=$(getent passwd "$TRANSMISSION_USER" | cut -d: -f6)

if test -z "$TRANSMISSION_HOME_DIR"
then
	echo Invalid user: $TRANSMISSION_USER
	exit 1
fi

# Resolve the VPN type: an explicit VPN_TYPE env var wins, otherwise auto-detect
# from the host config (WireGuard if /etc/wireguard/wg0.conf exists, else OpenVPN).
if test -z "$VPN_TYPE"
then
	if test -f /etc/wireguard/wg0.conf
	then
		VPN_TYPE=wireguard
	else
		VPN_TYPE=openvpn
	fi
fi

# Mount only the config directory for the selected VPN
if test "$VPN_TYPE" = "wireguard"
then
	VPN_MOUNT="-v /etc/wireguard:/etc/wireguard"
else
	VPN_MOUNT="-v /etc/openvpn:/etc/openvpn"
fi

echo "starting transmission with VPN_TYPE=$VPN_TYPE"

docker run \
$VPN_MOUNT \
-v $TRANSMISSION_HOME_DIR:/home/transmission \
-e VPN_TYPE=$VPN_TYPE \
-e XUID=$(id -u $TRANSMISSION_USER)  \
-e XGID=$(id -g $TRANSMISSION_USER) \
-e DNS1=$DNS1 \
-e DNS2=$DNS2 \
-e DNS3=$DNS3 \
--net=tvpn \
--ip=$IP_ADDR \
-p 9091:9091 \
--name=transmission \
--rm --privileged -d \
transmission /init.sh $NO_VPN_FLAG

exit $?
