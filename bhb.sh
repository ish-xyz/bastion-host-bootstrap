#!/bin/bash

#e.g.: FK2qgFMrvUt7an9lpg
bh_name="bastion-host"
tw_pass=$(head -c 13 /dev/urandom | base64 | tr -dc A-Za-z0-9)


setup_metadata() {
    # Setup SSH banner
    ##

    # Setup bation hostname
    echo ${bh_name} > /etc/hostname

}
