# Bastion Host configuration script

!['bastion-ow'](./img/bastion.png)

*From Wikipedia:*

*A bastion host is a special-purpose computer on a network specifically designed and configured to withstand attacks. The computer generally hosts a single application, for example a proxy server, and all other services are removed or limited to reduce the threat to the computer.*


This repository contains a bash script that will configure and install the required tools in your bastion host.

The script will perform the following actions:

* Install and configure the Intrusion Detection System (TripWire)
* Remove useless packages
* Setup iptables to only allow SSH, DNS, HTTP, and HTTPS
* Setup a crontab to run security update every day.
* Kernel tuning to:
    * Ignore ICMP ECHO (Disable PING)
    * Disable forward as this server doesn't needs to work as router/gateway (Also for MultiCast Packets)
    * Disable redirects (again it is not a router).
    * Disable source routing (should be already disabled by default)
    * Enable SYN flood protection
    * Smurf attack prevention
    * Log all martian packets
