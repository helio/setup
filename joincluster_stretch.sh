#!/bin/sh
set -e

# This script is meant for quick & easy install via:
#   $ curl -fsSL un.idling.host -o start-computing.sh
#   $ sh start-computing.sh
#
# install script to join our cluster
# TODO: replace wget with curl

# Input token from backend

# install required packages
read -r -p "[1] OK to install curl, wget, git, lsb-release, apt-transport-https package and dependencies? [Y/n]" PACKAGE
case "$PACKAGE" in
    [yY][eE][sS]|[yY])
	    printf "installing packages\n"
	    apt-get update
	    apt-get install curl wget lsb-release git apt-transport-https -y
        ;;
     *)
	printf "bummer\n"
        ;;
esac

# check for conflics
# e.g. installed puppet

# install puppet agent
read -r -p "[2] Continue with installing the puppet agent? [Y/n]" PUPPET
case "$PUPPET" in
    [yY][eE][sS]|[yY])
        printf "installing puppet\n"
	    wget https://apt.puppetlabs.com/puppet5-release-stretch.deb
	    dpkg -i puppet5-release-stretch.deb
	    apt-get update
            apt-get install puppet-agent=5.5.1-1stretch -y
        ;;
     *)
	printf "bummer\n"
        ;;
esac

# get JWT and create certificate & CSR
read -r -p "[3] OK request token from our backend and create a CSR? [Y/n]" CSR
case "$CSR" in
    [yY][eE][sS]|[yY])
        printf "requesting token ...\n"
	    #/etc/puppetlabs/puppet/csr_attributes.yaml
            /opt/puppetlabs/puppet/bin/puppet config set use_srv_records true
            /opt/puppetlabs/puppet/bin/puppet config set srv_domain idling.host
            /opt/puppetlabs/puppet/bin/puppet config set environment setupscript --section agent
            /opt/puppetlabs/bin/puppet agent --onetime
        ;;
     *)
	printf "bummer\n"
        ;;
esac


# Export metrics to our backend
#read -r -p "[4] We'd like to expose your system metrics to our plattform? [Y/n]" METRICS
#case "$METRICS" in
#    [yY][eE][sS]|[yY])
#        printf "downloading prometheus node exporter. running and exposing it on port 9100. Remember to allow access from IP 0.0.0.0/0\n"
#        wget https://bitbucket.org/kevinhaefeli2/setup/raw/529be465ef48237d3e45b4faff84df124cb0f137/node_exporter
#        chmod u+x node_exporter
#        ./node_exporter
#        ;;
#     *)
#        printf "bummer\n"
#        ;;
#esac

# Choose workload type (docker, pure binary)

# Deploy and join mcollective broker

# Check backend for sucess
# (based on mco ping answer)

# Install chosen workload type
# puppet apply docker script

# Get docker swarm settings from MCO / puppettask
# and join the swarm

# Run workload and earn money $$$

