#!/bin/bash
# install script to join our cluster

# Input token from backend

# install required packages
read -r -p "[1] OK to install curl, wget, git, lsb-release package and dependencies? [Y/n]" PACKAGE
case "$PACKAGE" in
    [yY][eE][sS]|[yY])
	printf "installing packages\n"
	apt-get update
	apt-get install curl wget lsb-release git -y
        ;;
     *)
	printf "bummer\n"
        ;;
esac

# install puppet agent
read -r -p "[2] OK to install puppet agent? [Y/n]" PUPPET
case "$PUPPET" in
    [yY][eE][sS]|[yY])
	printf "installing puppet\n"
	wget https://apt.puppetlabs.com/puppet5-release-jessie.deb
	dpkg -i puppet5-release-jessie.deb
	apt-get update
    	apt-get install puppet-agent=5.4.0-1jessie -y
        ;;
     *)
	printf "bummer\n"
        ;;
esac

# Export metrics to our backend

# Choose workload type (docker, pure binary)

# Deploy and join mcollective broker

# Check backend for sucess
# (based on mco ping answer)

# Install chosen workload type
# puppet apply docker script

# Get docker swarm settings from MCO / puppettask
# and join the swarm

# Run workload and earn money $$$

