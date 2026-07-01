#!/bin/sh

for arg in "$@"; do
	if [ "$arg" = "--no-vpn" ]
	then
		VPN_TYPE=none
	fi
done

if test $(id -u) -ne 0
then
	echo "You must run this as root"
	exit 1
fi

# Resolve which VPN to use. An explicit VPN_TYPE (env var or --no-vpn) wins;
# otherwise auto-detect from the mounted config: WireGuard if a wg0.conf is
# present, OpenVPN otherwise.
if test -z "$VPN_TYPE"
then
	if test -f /etc/wireguard/wg0.conf
	then
		VPN_TYPE=wireguard
	else
		VPN_TYPE=openvpn
	fi
fi
echo "using VPN_TYPE=$VPN_TYPE"


# create nameserver list
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

# change docker user's UID
if test $(id -u transmission) -ne $XUID
then
	echo changing uid
	usermod -o -u "$XUID" transmission
fi

# change docker user's GID
if test $(id -g transmission) -ne $XGID
then
	echo changing gid
	groupmod -g "$XGID" transmission
fi

# set the home directory
if test  "$(getent passwd transmission | cut -d: -f6)" != "/home/transmission"
then
	echo changing home dir
	usermod -d /home/transmission transmission
fi

# run the VPN + transmission daemon
# note that the daemon always runs as "transmission"

# start the kill-switch monitor for any VPN mode (it tears the VPN down when
# the public IP check fails, which makes the loop below rebuild the session)
if test "$VPN_TYPE" != "none"
then
	/monitor.sh "$VPN_TYPE" &
fi

# make sure transmission is not running before we start
pkill transmission

while :
do
	case "$VPN_TYPE" in
	openvpn)
		if test -z "$AUTHFILE"
		then
			AUTHFILE=auth.txt
		fi
		cd /etc/openvpn
		# openvpn stays in the foreground; --up starts the daemon once the tunnel is up
		openvpn --config default.vpn.ovpn --up "/usr/bin/su -l transmission -c transmission-daemon" --script-security 2 --auth-user-pass $AUTHFILE
		# make sure transmission is killed IMMEDIATELY after the VPN is closed so that it would not run
		# without the VPN even for a short while
		pkill transmission
		;;
	wireguard)
		# wg-quick returns as soon as the interface is configured, so we run the
		# daemon in the foreground and treat its exit as "tunnel gone": the monitor
		# kills transmission when the IP check fails, unblocking us to tear the
		# tunnel down and rebuild it. With AllowedIPs=0.0.0.0/0 wg-quick installs a
		# firewall kill-switch, so nothing leaks while the tunnel is up.
		wg-quick down wg0 2>/dev/null
		wg-quick up wg0
		/usr/bin/su -l transmission -c "transmission-daemon -f >/dev/null 2>&1"
		wg-quick down wg0 2>/dev/null
		pkill transmission
		;;
	none)
		/usr/bin/su -l transmission -c "transmission-daemon -f >/dev/null 2>&1"
		;;
	esac

	sleep 3
done
