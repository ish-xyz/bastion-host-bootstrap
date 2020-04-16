#!/bin/bash

#---------------------------------
#  ____  _   _ ____  ______ _   _ 
# |  _ \| | | |  _ \ \  ___) | | |
# | |_) ) |_| | |_) ) \ \  | |_| |
# |  _ (|  _  |  _ (   > > |  _  |
# | |_) ) | | | |_) ) / /__| | | |
# |____/|_| |_|____(_)_____)_| |_|
#---------------------------------
# Author: Isham J. Araia
# Date: Wed Apr 15 20:39:53 UTC 2020
# Description:
## Configure Bastion host for Amazon Linux 2 & CentOS 8 Server Minimal
## AWS tests:
## AMI -> ami-06ce3edf0cff21f07

set -e

if [[ ${BHB_DEBUG} == 1 ]]; then
    set -x
fi

# Const
BH_HOSTNAME="bastion-host"

# Temporary files
TMPF1=$(mktemp)

trap "rm -f ${TMPF1}" EXIT

## IDS/Tripware variables
tw_dir=/etc/tripwire
tw_site_key=${tw_dir}/site.key
tw_lcl_key=${tw_dir}/${BH_HOSTNAME}-local.key
tw_lcl_pass=$(head -c 13 /dev/urandom | base64 | tr -dc A-Za-z0-9)
tw_site_pass=$(head -c 13 /dev/urandom | base64 | tr -dc A-Za-z0-9)

removed_packages=(unzip GeoIP cloud-init perl-* make strace awscli bind-utils bzip2 zip postfix traceroute)

setup_metadata() {
    echo "Enter: ${FUNCNAME}"
    # Setup SSH banner
    cat <<EOF > /etc/ssh_banner
 ___ _  _ ___   ___ _  _ 
| _ ) || | _ ) / __| || |
| _ \ __ | _ \_\__ \ __ |
|___/_||_|___(_)___/_||_|
---------------------------
Authorized access only!
Disconnect IMMEDIATELY if you are not an authorized user!
All actions will be monitored and recorded.
---------------------------
EOF

    echo -e "\nBanner /etc/ssh_banner" >> /etc/ssh/sshd_config

    # Setup bation hostname
    echo ${BH_HOSTNAME} > /etc/hostname
    hostname ${BH_HOSTNAME}
    hostnamectl set-hostname ${BH_HOSTNAME}
    export HOSTNAME=${BH_HOSTNAME}
    echo "Exit: ${FUNCNAME}"
}

os_release() {
    # Print OS release
    eval $(cat /etc/os-release | sed -n 's/^ID=/OS_RELEASE=/p')
    echo $OS_RELEASE
}

remove_packages() {
    echo "Enter: ${FUNCNAME}"
    # On the Amazon linux 2 AMI we detected this packages as not useful for a Bastion Host 
    yum remove -y ${removed_packages}
    echo "Exit: ${FUNCNAME}"
}

configure_ids() {

    # This function will configure Tripwire Open Source as Intrusion Detection System.
    echo "Enter: ${FUNCNAME}"
    os_release

    if [[ ${OS_RELEASE} == "amzn" ]]; then
        amazon-linux-extras install epel -y
    elif [[ ${OS_RELEASE} == "centos" ]]; then
        yum install epel-release -y
    fi

    yum install -y tripwire

    # Prepare tripwire
    twadmin --generate-keys -Q ${tw_site_pass} --site-keyfile ${tw_site_key}
    twadmin --generate-keys -P ${tw_lcl_pass} --local-keyfile ${tw_lcl_key}
    twadmin --create-cfgfile -Q ${tw_site_pass} --cfgfile ${tw_dir}/tw.cfg \
        --site-keyfile ${tw_site_key} ${tw_dir}/twcfg.txt
    twadmin --create-polfile -Q ${tw_site_pass} --cfgfile ${tw_dir}/tw.cfg \
          --site-keyfile ${tw_site_key} ${tw_dir}/twpol.txt

    # Fixing keys and configuration permissions
    chown root:root ${tw_site_key} ${tw_lcl_key} ${tw_dir}/tw.cfg ${tw_dir}/tw.pol
    chmod 600 ${tw_site_key} ${tw_lcl_key} ${tw_dir}/tw.cfg ${tw_dir}/tw.pol

    # Initialize Tripwire
    tripwire --init -P ${tw_lcl_pass} -L ${tw_lcl_key}

    # Continue on errors
    set +e
    # Fix tripwire filesystem errors
    tripwire --check -L ${tw_lcl_key} | grep Filename > ${TMPF1}
    cat ${TMPF1} | awk {'print $2'} | while read l; do 
        echo "INFO: Tripwire conf search and replace ->  $l"; 
        sed -i "s@ $l @#$l @g" ${tw_dir}/twpol.txt
    done
    twadmin -m P -Q ${tw_site_pass} ${tw_dir}/twpol.txt
    tripwire --init -P ${tw_lcl_pass} -L ${tw_lcl_key}

    # Test if report gets generated
    rm -f /var/lib/tripwire/report/*.twr
    
    # Ignoring errors here
    tripwire --check -L ${tw_lcl_key}
    if [[ -z $(ls /var/lib/tripwire/report/*.twr) ]]; then
        echo "ERROR: Tripwire is not generating reports."
        exit 1
    fi
    set -e

    if ! [ -f "/etc/cron.daily/tripwire-check" ]; then
        echo "tripwire --check -L ${tw_lcl_key}" > /etc/cron.daily/tripwire-check
        chmod +x /etc/cron.daily/tripwire-check
    fi
    echo "Exit: ${FUNCNAME}"
}


setup_auto_sec_update() {
    echo "Enter: ${FUNCNAME}"
    # Run yum -y update --security every day
    echo 'yum -y update --security' > /etc/cron.daily/00-yum-update-security
    chmod +x /etc/cron.daily/00-yum-update-security
    echo "Exit: ${FUNCNAME}"
}

kernel_variables_setup() {
    echo "Enter: ${FUNCNAME}"

    # Ignore ICMP ECHO (Disable PING)
    sysctl -w net.ipv4.icmp_echo_ignore_all=1
    sysctl -w net.ipv6.icmp_echo_ignore_all=1

    # Disable forward as this server doesn't needs to be a router/gateway
    sysctl -w net.ipv4.conf.all.forwarding=0
    sysctl -w net.ipv6.conf.all.forwarding=0
    
    # We don't need to forward multicast packets, \
        # so there's no point to keep it enabled
    sysctl -w net.ipv4.conf.all.mc_forwarding=0
    sysctl -w net.ipv6.conf.all.mc_forwarding=0

    # Since it's not a router, we don't need to accept redirects. 
    sysctl -w net.ipv4.conf.all.accept_redirects=0
    sysctl -w net.ipv6.conf.all.accept_redirects=0
    
    # Disable source routing (should be already disabled by default)
    sysctl -w net.ipv4.conf.all.accept_source_route=0

    # Enable SYN flood protection
    sysctl -w net.ipv4.tcp_syncookies=1
    sysctl -w net.ipv4.tcp_synack_retries=5

    # Smurf attack prevention
    systctl -w net.ipv4.icmp_echo_ignore_broadcasts=1

    # Log all martian packets
    systctl -w net.ipv4.conf.all.log_martians=1

    echo "Exit: ${FUNCNAME}"
}


iptables_setup() {
    echo "Enter: ${FUNCNAME}"
    # Bastion host iptables setup

    IPT="/sbin/iptables"

    # flush all
    ${IPT} -t filter -F
    ${IPT} -t filter -X

    # Deny i/o
    ${IPT} -t filter -P INPUT DROP
    ${IPT} -t filter -P FORWARD DROP
    ${IPT} -t filter -P OUTPUT DROP

    # Allow outgoing http/s
    ${IPT} -A OUTPUT -p tcp -m tcp --dport 80 -j ACCEPT
    ${IPT} -A OUTPUT -p tcp -m tcp --dport 443 -j ACCEPT
    ${IPT} -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # SSH
    ${IPT} -t filter -A INPUT -p tcp --dport 22 -j ACCEPT
    ${IPT} -t filter -A OUTPUT -p tcp --sport 22 -j ACCEPT

    # Allow DNS queries

    for dnsip in $(cat /etc/resolv.conf | grep ^nameserver | awk {'print $2'}); do
        echo "Allowing DNS lookups (tcp, udp port 53) to server '$ip'"
        ${IPT} -A OUTPUT -p udp -d ${dnsip} --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
        ${IPT} -A INPUT  -p udp -s ${dnsip} --sport 53 -m state --state ESTABLISHED     -j ACCEPT
        ${IPT} -A OUTPUT -p tcp -d ${dnsip} --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
        ${IPT} -A INPUT  -p tcp -s ${dnsip} --sport 53 -m state --state ESTABLISHED     -j ACCEPT
    done
    
    # Prevent SYN Flooding
    ${IPT} -A INPUT -i eth0 -p tcp --syn -m limit --limit 5/second -j ACCEPT
    echo "Exit: ${FUNCNAME}"
}


#Must be executed as root
if [[  $USER != "root" ]]; then
    echo "ERROR: Permission denied. The script must be executed as root"
    exit 1    
fi

if [[ -n $1 ]]; then
    echo "Argument/Config File detected. Loading it."
    source $1
fi

setup_metadata

if [[ ${AUTO_SEC_UPDATE} != 0 ]]; then
    setup_auto_sec_update
fi

if [[ ${REMOVE_PACKAGES} != 0 ]]; then
    remove_packages
fi

if [[ ${IDS} != 0 ]]; then
    configure_ids
fi

if [[ ${KERNEL_TUNING} != 0 ]]; then
    kernel_variables_setup
fi

if [[ ${IPTABLES} != 0 ]]; then
    iptables_setup
fi

if [[ ${REBOOT} != 0 ]]; then
    reboot
fi


echo "----"
echo "tripware local passphrase -> ${tw_lcl_pass}"
echo "tripware site passphrase -> ${tw_site_pass}"
echo "----"