#!/bin/sh

for arg in "$@"; do
	if [ "$arg" = "--no-vpn" ]
	then
		NOVPN=true
	fi
done

if test $(id -u) -ne 0
then
	echo "You must run this as root"
	exit 1
fi


#create nameserver list
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

# we want the docker image user "transmission" to have the UID and GID
# of the host transmission user (which may have another name in the host) so that
# the dokcer user would have permission to access the host user's resources

#change docker user's UID
if test $(id -u transmission) -ne $XUID
then
	echo changing uid
	usermod -o -u "$XUID" transmission
fi

#change docker user's GID
if test $(id -g transmission) -ne $XGID
then
	echo changing gid
	groupmod -g "$XGID" transmission
fi

#set the home directory
if test  "$(getent passwd transmission | cut -d: -f6)" != "/home/transmission"
then
	echo changing home dir
	usermod -d /home/transmission transmission
fi

#run openvpn + transmission daemon
#note that the daemon runs as "transmission"

if test -z $NOVPN
then
	if test -z "$AUTHFILE"
	then
		AUTHFILE=auth.txt
	fi

	cd /etc/openvpn

	/monitor.sh &
fi

while :
do
	pkill transmission

	if test -z $NOVPN
	then
		openvpn --config default.vpn.ovpn --up "/usr/bin/su -l transmission -c transmission-daemon" --script-security 2 --auth-user-pass $AUTHFILE
	else
		/usr/bin/su -l transmission -c "transmission-daemon -f >/dev/null 2>&1"
	fi

	sleep 3
done
