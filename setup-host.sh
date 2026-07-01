#!/bin/sh

# Prepares the Docker host to run transmission-openvpn: creates the local
# transmission user and its RPC configuration (if they don't already exist),
# then writes a start-transmission.sh in the current directory that launches
# exec.sh with the given DNS servers, IP, and user already filled in.
#
# Run from the repo directory (same as install.sh/exec.sh).
#
# Usage: ./setup-host.sh [--user NAME] [--ip ADDR] [--dns1 DNS] [--dns2 DNS] [--dns3 DNS]

if test $(id -u) -ne 0
then
	echo "You must run this as root"
	exit 1
fi

TRANSMISSION_USER=transmission
IP_ADDR=172.18.0.2
DNS1=1.1.1.1
DNS2=84.200.70.40
DNS3=1.0.0.1

while test $# -gt 0
do
	case "$1" in
	--user)
		TRANSMISSION_USER=$2
		shift 2
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
	*)
		echo "Unknown argument: $1"
		exit 1
		;;
	esac
done

# create the transmission user if it doesn't already exist
if ! getent passwd "$TRANSMISSION_USER" >/dev/null
then
	echo "creating user $TRANSMISSION_USER"
	useradd -m "$TRANSMISSION_USER"
fi

TRANSMISSION_HOME_DIR=$(getent passwd "$TRANSMISSION_USER" | cut -d: -f6)

# ensure home directory exists and is searchable by all users
mkdir -p "$TRANSMISSION_HOME_DIR"
chmod 755 "$TRANSMISSION_HOME_DIR"

# create torrent and download directories (readable by all users)
TORRENTS_DIR="$TRANSMISSION_HOME_DIR/torrents"
DOWNLOADS_DIR="$TRANSMISSION_HOME_DIR/downloads"
mkdir -p "$TORRENTS_DIR" "$DOWNLOADS_DIR"
chmod 755 "$TORRENTS_DIR" "$DOWNLOADS_DIR"
chown "$TRANSMISSION_USER":"$TRANSMISSION_USER" "$TORRENTS_DIR" "$DOWNLOADS_DIR"

CONFIG_DIR="$TRANSMISSION_HOME_DIR/.config/transmission-daemon"
SETTINGS_FILE="$CONFIG_DIR/settings.json"

# create the RPC configuration if it doesn't already exist, so the web
# interface is reachable (rpc-bind-address 0.0.0.0) and secured with
# generated credentials and a whitelist matching the container's subnet
if test ! -f "$SETTINGS_FILE"
then
	echo "creating $SETTINGS_FILE"
	mkdir -p "$CONFIG_DIR"

	RPC_SUBNET=$(echo "$IP_ADDR" | cut -d. -f1-3)
	RPC_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)

	cat > "$SETTINGS_FILE" <<-EOF
	{
	    "download-dir": "$TORRENTS_DIR",
	    "incomplete-dir": "$DOWNLOADS_DIR",
	    "incomplete-dir-enabled": true,
	    "rpc-enabled": true,
	    "rpc-bind-address": "0.0.0.0",
	    "rpc-port": 9091,
	    "rpc-whitelist-enabled": true,
	    "rpc-whitelist": "127.0.0.1,$RPC_SUBNET.*",
	    "rpc-authentication-required": true,
	    "rpc-username": "$TRANSMISSION_USER",
	    "rpc-password": "$RPC_PASSWORD"
	}
	EOF

	chown -R "$TRANSMISSION_USER":"$TRANSMISSION_USER" "$TRANSMISSION_HOME_DIR/.config"
	chmod 600 "$SETTINGS_FILE"

	echo "web interface credentials: $TRANSMISSION_USER / $RPC_PASSWORD"
	echo "(stored in $SETTINGS_FILE - edit rpc-whitelist there too if your LAN subnet differs)"
fi

# write the start script with the DNS/IP/user settings baked in as exec.sh flags
START_SCRIPT="start-transmission.sh"
cat > "$START_SCRIPT" <<-EOF
	#!/bin/sh
	exec ./exec.sh --dns1 "$DNS1" --dns2 "$DNS2" --dns3 "$DNS3" --ip "$IP_ADDR" "\$@" "$TRANSMISSION_USER"
EOF
chmod +x "$START_SCRIPT"

echo "wrote $START_SCRIPT"
