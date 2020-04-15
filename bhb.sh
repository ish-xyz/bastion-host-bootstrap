#!/bin/bash
#
##
## Configure Bastion host for Amazon Linux 2 & CentOS
## Testing on ami-06ce3edf0cff21f07

set -e

if [[ ${BHB_LOG} == "debug" ]]; then
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

sanity_checks() {
    #must be executed as root
    if [[  $USER != "root" ]]; then
        echo "ERROR: Permission denied. The script must be executed as root"
        exit 1
    fi
}

setup_metadata() {
    # Setup SSH banner
    
    # Setup bation hostname
    echo ${BH_HOSTNAME} > /etc/hostname
    hostname ${BH_HOSTNAME}
    hostnamectl set-hostname ${BH_HOSTNAME}
    export HOSTNAME=${BH_HOSTNAME}
}

os_release() {
    # Print OS release
    eval $(cat /etc/os-release | sed -n 's/^ID=/OS_RELEASE=/p')
    echo $OS_RELEASE
}

remove_useless_packages() {
    # On the Amazon linux 2 AMI we detected this packages as not useful for a Bastion Host 
    yum remove -y ${removed_packages}
}

configure_ids() {

    # This function will configure Tripwire Open Source as Intrusion Detection System.

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
    tripwire --check -L ${tw_lcl_key}
    if [[ -z $(ls /var/lib/tripwire/report/*.twr) ]]; then
        echo "ERROR: Tripwire is not generating reports."
        exit 1
    fi

    if ! [ -f "/etc/cron.daily/tripwire-check" ]; then
        echo "tripwire --check -L ${tw_lcl_key}" > /etc/cron.daily/tripwire-check
    fi
}


enable_rp_filtering() {
    # Usually is enabled by default - but still we want to make sure that the rp_filter is enabled.
    echo "rp_filter"
}

sanity_checks
setup_metadata
configure_ids