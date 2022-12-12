#!/bin/sh

if test -z "$1"
then
	DOCKER_BASE_IMAGE=ubuntu
else
	DOCKER_BASE_IMAGE=$1
fi

#stop existing transmission instance
docker kill transmission 2>/dev/null

#remove exiting transmission image
docker image rm transmission 2>/dev/null

#make sure there is no init image
docker rm -f transmission-init 2>/dev/null

#run init image
docker run -dit --name=transmission-init --rm $DOCKER_BASE_IMAGE bash

#copy files
docker cp init.sh transmission-init:/init.sh
docker cp checkip.sh transmission-init:/checkip.sh
docker cp monitor.sh transmission-init:/monitor.sh

#install packages
docker exec transmission-init apt update
docker exec transmission-init apt install curl openvpn transmission-daemon -y

#add transmission user
docker exec -it transmission-init adduser --no-create-home --disabled-password -q transmission

#create transmission image
docker commit transmission-init transmission

#cleanup
docker rm -f transmission-init
