# transmission-openvpn

It is assumed that the host has openvpn configuration which includes default.vpn.ovpn with configuration for automatic connection to a VPN.
It is assumed that the host has a user with vaild transmission configuration.
It is assumed that the user is transmission and that the openvpn configuration is at /etc/openvpn.
It is assumed that a bridge network whose name is docker18 (172.18.0.0/16) was created.
The VPN will run with root permissions.
Transmission will run with the permissions of the transmission user.

