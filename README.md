# Bastion Host configuration script

*From Wikipedia:*

*A bastion host is a special-purpose computer on a network specifically designed and configured to withstand attacks. The computer generally hosts a single application, for example a proxy server, and all other services are removed or limited to reduce the threat to the computer.*


This repository contains a bash script that will configure and install the required tools in your bastion host.

If you run on AWS it will also configure the CloudWatch Agent to export logs.

The script will perform the following actions:

* Install tripwire as IDS (Intrusion Detection System).
* 