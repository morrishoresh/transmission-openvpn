# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This project builds and runs a Docker container that runs the Transmission BitTorrent daemon behind a VPN tunnel — either **OpenVPN** or **WireGuard**. The design guarantees that Transmission only ever has network access through the VPN: if the VPN drops, Transmission is killed immediately so it never leaks traffic over the host's real connection.

**VPN selection.** The VPN type is resolved (in both `exec.sh` and `init.sh`) as: explicit `VPN_TYPE` env var (`openvpn`|`wireguard`) wins; otherwise auto-detect — WireGuard if `/etc/wireguard/wg0.conf` exists, else OpenVPN. The `--no-vpn` flag (or `VPN_TYPE=none`) runs the daemon with no tunnel.

The entire project is a handful of POSIX `sh` scripts (`#!/bin/sh`) — there is no build system, package manifest, or test suite. Scripts run on the Docker host except `init.sh`, `monitor.sh`, and `checkip.sh`, which run *inside* the container.

## Commands

```sh
# 1. Build the "transmission" Docker image (installs curl, openvpn, transmission-daemon).
#    Optional arg overrides the base image (default: ubuntu).
./install.sh [base-image]

# 2. Start the container. Optional flags:
#    -s [seconds]      wait/sleep before starting (e.g. -s 30 to delay on boot)
#    [transmission-user]  host user whose home dir holds Transmission data (default: transmission)
./exec.sh [-s [seconds]] [transmission-user]
```

There is no lint or test tooling; validate script changes manually (e.g. `sh -n script.sh` for a syntax check).

## Architecture

**Two-phase lifecycle: build (`install.sh`) then run (`exec.sh`).**

`install.sh` runs on the host. It spins up a temporary `transmission-init` container from the base image, copies `init.sh`, `checkip.sh`, and `monitor.sh` into it, installs the packages (`openvpn`, `transmission-daemon`, `wireguard-tools`, plus `iproute2`/`iptables` for `wg-quick`), creates a `transmission` user, then `docker commit`s the result as the `transmission` image and discards the init container. The WireGuard kernel module is *not* installed — it comes from the host kernel via `--privileged`.

`exec.sh` runs on the host and launches the committed image. Key wiring:
- Resolves `VPN_TYPE` (env override, else auto-detect from host config) and mounts **only** the selected VPN's config dir: host `/etc/wireguard` or `/etc/openvpn` → same path in the container. Passes `VPN_TYPE` into the container so `init.sh` doesn't re-detect differently.
- Mounts the host Transmission user's home dir → container `/home/transmission` (torrent data/config).
- Passes `XUID`/`XGID` (host user's UID/GID) so the in-container `transmission` user matches host file ownership.
- Attaches to a pre-existing Docker network `tvpn` with static IP `172.18.0.2`, publishes the RPC port with `-p 9091:9091`, runs `--privileged` (required for the TUN device / WireGuard), and sets container entrypoint to `/init.sh`.

**Container entrypoint: `init.sh`** (PID 1 inside the container, runs as root):
1. Resolves `VPN_TYPE` (same logic as `exec.sh`; `--no-vpn` maps to `none`).
2. Writes `/etc/resolv.conf` from `DNS1`/`DNS2`/`DNS3` env vars (prevents DNS leaks outside the VPN). This is why WireGuard configs must **not** carry a `DNS =` line — DNS is owned here, and `wg-quick` would otherwise need `resolvconf`.
3. Uses `usermod`/`groupmod` to align the container `transmission` user's UID/GID/home with the host values from `XUID`/`XGID`.
4. Starts `monitor.sh $VPN_TYPE` in the background for any VPN mode.
5. Enters an infinite supervision loop, branching on `VPN_TYPE`:
   - **openvpn**: runs OpenVPN in the foreground with `--up` starting `transmission-daemon`. When OpenVPN exits, `pkill transmission` fires immediately, then reconnects after 3s.
   - **wireguard**: `wg-quick up wg0`, then runs `transmission-daemon -f` in the *foreground* (since `wg-quick` returns immediately). When the daemon exits — the monitor kills it on tunnel loss — the loop runs `wg-quick down wg0`, `pkill transmission`, and re-ups. Requires `AllowedIPs = 0.0.0.0/0` in the config so `wg-quick` installs its firewall kill-switch.
   - **none**: just runs the daemon, no tunnel.

**Kill-switch monitoring: `monitor.sh` + `checkip.sh`.** `monitor.sh $VPN_TYPE` polls every 60s; `checkip.sh` hits `checkip.amazonaws.com` for the current public IP. If no IP comes back (VPN likely down): for OpenVPN it kills the OpenVPN process (unblocking the loop); for WireGuard it `pkill transmission`s (WireGuard has no long-running process to kill — killing the foregrounded daemon is what unblocks the loop to tear the tunnel down and rebuild).

## Conventions & Constraints

- Scripts are POSIX `sh`, not bash — keep them portable (`test`, `[ ]`, no bashisms).
- OpenVPN config is expected at `/etc/openvpn/default.vpn.ovpn` with credentials at the file named by `$AUTHFILE` (default `auth.txt`, resolved relative to `/etc/openvpn`). WireGuard config is expected at `/etc/wireguard/wg0.conf` (interface `wg0`).
- WireGuard configs must use `AllowedIPs = 0.0.0.0/0` (for the kill-switch) and must omit any `DNS =` line (DNS is handled via env vars in `init.sh`).
- Web interface (RPC, port 9091): `exec.sh` publishes it (`-p 9091:9091`), so Docker handles the host-side DNAT/MASQUERADE/FORWARD rules automatically — no manual host iptables needed. Requires `rpc-bind-address: 0.0.0.0` + a whitelist in `settings.json` matching the real client source IP (Docker preserves it for external LAN connections; only the loopback/hairpin case appears as the gateway `172.18.0.1`). Separately, under WireGuard the `wg-quick` kill-switch REJECTs the container's replies regardless of how the connection got in (they don't leave via `wg0`), so a `PostUp = iptables -I OUTPUT -d <tvpn-subnet> -j ACCEPT` is needed in `wg0.conf` (not needed for OpenVPN, which installs no such rule). See README "Web interface".
- The Docker network `tvpn` and IP `172.18.0.2` in `exec.sh` are environment-specific assumptions, not created by these scripts (see the README for how to create the network).
- The security invariant throughout is *no Transmission traffic without an active VPN* — preserve the immediate-kill and DNS-override behavior when editing `init.sh` or `monitor.sh`.
