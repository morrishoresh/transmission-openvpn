#!/bin/sh
docker cp init.sh $1:/init.sh
docker cp checkip.sh $1:/checkip.sh
docker exec $1 apt update
docker exec $1 apt install curl openvpn transmission-daemon -y
docker exec -it $1 adduser --no-create-home --disabled-password -q transmission
docker commit $1 transmission
