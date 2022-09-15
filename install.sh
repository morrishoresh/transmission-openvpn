#!/bin/sh

docker image rm transmission 2>/dev/null
docker rm -f transmission-init 2>/dev/null
docker run -dit --name=transmission-init --rm ubuntu bash
docker cp init.sh transmission-init:/init.sh
docker cp checkip.sh transmission-init:/checkip.sh
docker exec transmission-init apt update
docker exec transmission-init apt install curl openvpn transmission-daemon -y
docker exec -it transmission-init adduser --no-create-home --disabled-password -q transmission
docker commit transmission-init transmission
docker rm -f transmission-init
