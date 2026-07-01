#!/bin/sh

# Prepares the Docker host to run transmission-openvpn: creates the local
# transmission user and its RPC configuration (if they don't already exist),
# then writes a start-transmission.sh in the current directory that launches
# exec.sh with the given DNS servers, IP, and user already filled in.
#
# Run from the repo directory (same as install.sh/exec.sh).
#
# Usage: ./setup-host.sh [--user NAME] [--ip ADDR] [--dns1 DNS] [--dns2 DNS] [--dns3 DNS] [--rpc-user USER] [--rpc-password PASS] [--no-rpc-auth]
#
# --no-rpc-auth: disable RPC authentication and whitelist all addresses (for secure networks only)

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
RPC_USER=""
RPC_PASSWORD=""
NO_RPC_AUTH=false

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
	--rpc-user)
		RPC_USER=$2
		shift 2
		;;
	--rpc-password)
		RPC_PASSWORD=$2
		shift 2
		;;
	--no-rpc-auth)
		NO_RPC_AUTH=true
		shift
		;;
	*)
		echo "Unknown argument: $1"
		exit 1
		;;
	esac
done

# default RPC user to the transmission user if not specified
if test -z "$RPC_USER"
then
	RPC_USER=$TRANSMISSION_USER
fi

# create the transmission user if it doesn't already exist
if ! getent passwd "$TRANSMISSION_USER" >/dev/null
then
	echo "creating user $TRANSMISSION_USER"
	useradd -m "$TRANSMISSION_USER"
fi

TRANSMISSION_HOME_DIR=$(getent passwd "$TRANSMISSION_USER" | cut -d: -f6)

# ensure home directory is searchable by all users
chmod 755 "$TRANSMISSION_HOME_DIR"

# create torrent and download directories (readable by all users)
TORRENTS_DIR="$TRANSMISSION_HOME_DIR/torrents"
DOWNLOADS_DIR="$TRANSMISSION_HOME_DIR/downloads"
mkdir -p "$TORRENTS_DIR" "$DOWNLOADS_DIR"
chmod 755 "$TORRENTS_DIR" "$DOWNLOADS_DIR"
chown "$TRANSMISSION_USER":"$TRANSMISSION_USER" "$TORRENTS_DIR" "$DOWNLOADS_DIR"

CONFIG_DIR="$TRANSMISSION_HOME_DIR/.config/transmission-daemon"
SETTINGS_FILE="$CONFIG_DIR/settings.json"

# create/overwrite the RPC configuration so the web interface is reachable
mkdir -p "$CONFIG_DIR"

if test "$NO_RPC_AUTH" = "true"
then
	# no authentication, no whitelist (assumes secure network)
	cat > "$SETTINGS_FILE" <<-EOF
	{
	    "download-dir": "$TORRENTS_DIR",
	    "incomplete-dir": "$DOWNLOADS_DIR",
	    "incomplete-dir-enabled": true,
	    "rpc-enabled": true,
	    "rpc-bind-address": "0.0.0.0",
	    "rpc-port": 9091,
	    "rpc-whitelist-enabled": false,
	    "rpc-authentication-required": false
	}
	EOF
	echo "web interface: no authentication, all addresses allowed"
else
	# generate a password if one wasn't provided
	if test -z "$RPC_PASSWORD"
	then
		RPC_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
	fi

	RPC_SUBNET=$(echo "$IP_ADDR" | cut -d. -f1-3)

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
	    "rpc-username": "$RPC_USER",
	    "rpc-password": "$RPC_PASSWORD"
	}
	EOF
	echo "web interface credentials: $RPC_USER / $RPC_PASSWORD"
	echo "(stored in $SETTINGS_FILE - edit rpc-whitelist there too if your LAN subnet differs)"
fi

chown -R "$TRANSMISSION_USER":"$TRANSMISSION_USER" "$TRANSMISSION_HOME_DIR/.config"
chmod 600 "$SETTINGS_FILE"

# write the start script with the DNS/IP/user settings baked in as exec.sh flags
START_SCRIPT="start-transmission.sh"
cat > "$START_SCRIPT" <<-EOF
	#!/bin/sh
	exec ./exec.sh --dns1 "$DNS1" --dns2 "$DNS2" --dns3 "$DNS3" --ip "$IP_ADDR" "\$@" "$TRANSMISSION_USER"
EOF
chmod +x "$START_SCRIPT"

echo "wrote $START_SCRIPT"
