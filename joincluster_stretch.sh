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
        read -r -p "token: " token
        printf "custom_attributes:\n  challengePassword: \"$token\"" >> /etc/puppetlabs/puppet/csr_attributes.yaml
        /opt/puppetlabs/puppet/bin/puppet config set certname token.idling.host
        /opt/puppetlabs/puppet/bin/puppet config set use_srv_records true
        /opt/puppetlabs/puppet/bin/puppet config set srv_domain idling.host
        /opt/puppetlabs/puppet/bin/puppet config set environment setupscript --section agent
        ;;
     *)
	printf "bummer\n"
        ;;
esac


# Export metrics to our backend
read -r -p "[4] We'd like to expose your system metrics to our plattform? [Y/n]" METRICS
case "$METRICS" in
    [yY][eE][sS]|[yY])
        printf "downloading prometheus node exporter. running and exposing it on port 9100. Remember to allow access from IP 0.0.0.0/0\n"
        /opt/puppetlabs/puppet/bin/puppet resource package prometheus-node-exporter ensure=present
        /opt/puppetlabs/puppet/bin/puppet resource service prometheus-node-exporter ensure=running enable=true
        # exporting resource to puppetdb or ping api?
        ;;
     *)
        printf "bummer\n"
        ;;
esac


# Choose workload type (docker, pure binary)
printf "[5] How should we deploy the computing on your node? \n"
read -r -p "Choose 1 [Docker] 2 [Service] 3 [Stop]" WORKLOAD
case "$WORKLOAD" in
    [1])
        echo "Going to install Docker"
        /opt/puppetlabs/puppet/bin/puppet agent -t
        ;;
    [2])
        echo "Option not available yet"
        ;;
    [3])
        echo "bummer"
        ;;
    *)
        printf "bummer\n"
        ;;
 esac

# Install chosen workload type
# puppet apply docker script

# Get docker swarm settings from MCO / puppettask
# and join the swarm

# Check backend for sucess
# (based on mco ping answer)

# Deploy and join mcollective broker

# Run workload and earn money $$$

