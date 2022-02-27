#!/bin/sh

docker run \
-v /etc/openvpn:/etc/openvpn \
-v /home/transmission:/home/transmission \
-e XUID=$(id -u transmission)  \
-e XGID=$(id -g transmission) \
-e DNS1=1.1.1.1 \
-e DNS2=84.200.70.40 \
-e DNS3=1.0.0.1 \
--net=docker18 \
--ip=172.18.0.2 \
--name=transmission \
--rm --privileged -d \
transmission /init.sh


