# transmission-openvpn

Runs the Transmission daemon behind a VPN (OpenVPN or WireGuard). Transmission never has network access without an active tunnel. <br /> <br />

The VPN type is auto-detected: if /etc/wireguard/wg0.conf exists WireGuard is used, otherwise OpenVPN. Set the VPN_TYPE env var (openvpn|wireguard|none) to force one (or use --no-vpn flag). <br /> <br />

OpenVPN: the host must have configuration in /etc/openvpn/default.vpn.ovpn <br />
WireGuard: the host must have configuration in /etc/wireguard/wg0.conf, and the host kernel must support WireGuard (built into Linux 5.6+). Do NOT put a "DNS =" line in wg0.conf — DNS is set from the DNS1/DNS2/DNS3 env vars. Use AllowedIPs = 0.0.0.0/0 so wg-quick installs its kill-switch. <br />

Environment variables (set inside the container by `exec.sh`, not by hand): <br /> <br />
VPN_TYPE: openvpn, wireguard, or none. Overrides auto-detection. <br />
AUTHFILE: the OpenVPN user authentication. default is /etc/openvpn/auth.txt <br />
DNS1, DNS2, DNS3: DNS servers. Set via `exec.sh`'s `--dns1`/`--dns2`/`--dns3` flags, see below. <br />
XUID: the UID of the transmission user on the host <br />
XGID: the GID of the transmission user on the host <br />

## Setup and usage

Follow these steps in order. Steps 1–4 run once; step 6 runs every time you start the container.

### 1. Build the Docker image

```sh
./install.sh [base-image]
```

Builds the `transmission` Docker image with Transmission, OpenVPN, WireGuard tools, and other dependencies. Optional `base-image` defaults to `ubuntu`. If the base image doesn't exist locally, Docker automatically pulls it from Docker Hub — no need to download it yourself.

### 2. Create the Docker network

```sh
docker network create --subnet=172.18.0.0/24 tvpn
```

Creates the `tvpn` network that the container attaches to. The default subnet is `172.18.0.0/24` with the container at `172.18.0.2`, but you can use any subnet. For example:

```sh
# Use a different subnet (e.g., 192.168.2.0/24):
docker network create --subnet=192.168.2.0/24 tvpn
```

If you use a different subnet, you must also pass the matching `--ip` to `setup-host.sh` and `exec.sh` (e.g., `--ip 192.168.2.2`).

### 3. Prepare the VPN configuration on the host (or skip for no-VPN mode)

The container expects the VPN config to be mounted from the host. Place it in one of:

- **OpenVPN**: `/etc/openvpn/default.vpn.ovpn` with credentials in `/etc/openvpn/auth.txt` (format: `username` on line 1, `password` on line 2)
- **WireGuard**: `/etc/wireguard/wg0.conf` (must include `AllowedIPs = 0.0.0.0/0` for the kill-switch; do NOT include a `DNS =` line)

The VPN type is auto-detected from which config file exists.

### 4. Run setup-host.sh to configure the Transmission user and RPC

```sh
# With RPC authentication (secure):
sudo ./setup-host.sh --rpc-user admin --rpc-password mypassword

# Without RPC authentication (for secure networks only):
sudo ./setup-host.sh
```

This must run as root. It:
- Creates the `transmission` user on the host (if missing)
- Creates `/home/transmission/torrents` and `/home/transmission/downloads` directories (world-readable)
- Generates `~transmission/.config/transmission-daemon/settings.json` with the given RPC settings
- Writes `start-transmission.sh` in the current directory, embedding the DNS/IP/user settings for convenience

**Parameters and defaults:**
- `--user` (default: `transmission`) — host user name
- `--ip` (default: `172.18.0.2`) — container IP on the tvpn network
- `--dns1`, `--dns2`, `--dns3` (defaults: `1.1.1.1`, `84.200.70.40`, `1.0.0.1`) — DNS servers in the container
- `--rpc-user` (no default) — Transmission RPC username (required if using `--rpc-password`)
- `--rpc-password` (no default) — Transmission RPC password (required if using `--rpc-user`)

**RPC authentication rules:**
- If you provide both `--rpc-user` and `--rpc-password`: authentication is required, and the provided credentials are used
- If you provide neither: authentication is disabled (assumes you're on a secure network)
- If you provide only one: an error is raised

### 5. Verify the configuration

Edit `~transmission/.config/transmission-daemon/settings.json` if needed (e.g., to add LAN subnet access). The file is created with:
- `rpc-enabled: true`
- `rpc-bind-address: 0.0.0.0` (reachable over the Docker network)
- `rpc-port: 9091`
- `rpc-whitelist-enabled: false` (no IP-based filtering; use authentication instead)

### 6. Start the container

```sh
./start-transmission.sh
```

This runs `exec.sh` with the DNS/IP/user settings from step 4 already baked in. The container will:
- Mount the VPN config from `/etc/openvpn` or `/etc/wireguard`
- Mount the transmission user's home directory
- Start the VPN tunnel
- Launch Transmission behind it
- Kill Transmission immediately if the tunnel drops (no traffic leak)

**To run without a VPN (testing only):**
```sh
./start-transmission.sh --no-vpn
```

This skips the VPN tunnel entirely. Not recommended for production.

## Network

`exec.sh` attaches the container to a Docker network named `tvpn` at a static IP (default `172.18.0.2` on the `172.18.0.0/24` subnet). This network is not created by the scripts — you must create it once on the host before running the container.

The default setup:
```sh
docker network create --subnet=172.18.0.0/24 tvpn
```

**Custom subnet example:** If you want to use a different subnet (e.g., `192.168.2.0/24`):

```sh
# 1. Create network with custom subnet
docker network create --subnet=192.168.2.0/24 tvpn

# 2. Run setup-host.sh with matching IP
sudo ./setup-host.sh --ip 192.168.2.2 [other options]

# 3. The container will use 192.168.2.2 on startup
./start-transmission.sh
```

The key is: **the IP you pass to `setup-host.sh` must be within the subnet you created for the `tvpn` network.**

Verify the network exists:
```sh
docker network ls
```

## Web interface

The Transmission RPC / web interface listens on port 9091. `exec.sh` publishes it with `-p 9091:9091`, so you can reach it at `http://<host-address>:9091`. Two things must be set up:
1. **Transmission RPC settings** — done by `setup-host.sh` in step 4 (authentication if you provide credentials, or open if you don't)
2. **WireGuard kill-switch exception** (WireGuard only) — see below

### Transmission (`settings.json`)

The file is created by `setup-host.sh` (step 4 above) at:

```
~transmission/.config/transmission-daemon/settings.json
```

**Important:** Transmission overwrites this file when it exits, so stop the container before editing:

```sh
docker kill transmission
# edit settings.json as needed
./start-transmission.sh              # restart
```

Key settings (auto-generated by `setup-host.sh`):
- `rpc-enabled: true` — RPC interface is enabled
- `rpc-bind-address: "0.0.0.0"` — listens on all interfaces
- `rpc-port: 9091`
- `rpc-whitelist-enabled: false` — no IP-based filtering (authentication or network security is the gate)
- `rpc-authentication-required` — true if you supplied `--rpc-user` and `--rpc-password`, false otherwise
- `download-dir` — points to `~/torrents` (completed torrents)
- `incomplete-dir` — points to `~/downloads` (active downloads)

You can edit these values directly, but remember Transmission will rewrite the file on exit (and will hash the password if changed).

### WireGuard kill-switch exception (WireGuard only)

With `AllowedIPs = 0.0.0.0/0`, `wg-quick` installs a firewall kill-switch that **rejects any outbound packet not leaving through the `wg0` tunnel**. This includes RPC replies going back over the Docker network, which would otherwise fail.

To allow the web interface to work, add this `PostUp` rule to the `[Interface]` section of `/etc/wireguard/wg0.conf`:

```ini
PostUp = iptables -I OUTPUT -d 172.18.0.0/24 -j ACCEPT
```

Use the same subnet you created the `tvpn` network with (step 2). After editing `wg0.conf`, restart the container for the change to take effect:

```sh
docker kill transmission
./start-transmission.sh
```

(OpenVPN does not install a kill-switch, so this step is not needed for OpenVPN.)

