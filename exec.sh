#!/bin/sh

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

docker run \
-v /etc/openvpn:/etc/openvpn \
-v $TRANSMISSION_HOME_DIR:/home/transmission \
-e XUID=$(id -u $TRANSMISSION_USER)  \
-e XGID=$(id -g $TRANSMISSION_USER) \
-e DNS1=1.1.1.1 \
-e DNS2=84.200.70.40 \
-e DNS3=1.0.0.1 \
--net=docker18 \
--ip=172.18.0.2 \
--name=transmission \
--rm --privileged -d \
transmission /init.sh

exit $?
