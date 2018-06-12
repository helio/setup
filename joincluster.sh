#!/bin/sh
set -e

# This script is meant for quick & easy install via:
#   $ curl -fsSL un.idling.host -o start-computing.sh
#   $ sh start-computing.sh
#
# install script to join our cluster
# TODO: replace wget with curl

# our default functions
command_exists() {
	command -v "$@" > /dev/null 2>&1
}

get_distribution() {
	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	echo "$lsb_dist"
}

# supported & tested distros
DISTRO_MAP="
x86_64-debian-jessie
x86_64-debian-stretch
"

# required packages
reqs="apt-transport-https ca-certificates curl git lsb-release"

# Platform detection
lsb_dist=$( get_distribution )
lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

# check for conflics
# e.g. installed puppet
read -r -p "[1] Checking for conflicts [Y/n]" CHECK
case "$CHECK" in
    [yY][eE][sS]|[yY])
        if command_exists puppet; then
            printf "puppet is already installed, only continue if it's OK to overwrite settings \n"
        fi
    *)
	printf "bummer\n"
        ;;
esac

# check requirements
if [ "$user" != 'root' ]; then
    if command_exists sudo; then
        sh_c='sudo -E sh -c'
    elif command_exists su; then
        sh_c='su -c'
    else
        cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
			exit 1
    fi
fi

# install required packages
read -r -p "[0] The following packages and dependencies are going to be installed: $reqs [Y/n]" PACKAGE
case "$PACKAGE" in
    [yY][eE][sS]|[yY])
	    printf "installing packages\n"
        apt-get update -qq >/dev/null
        apt-get install -y -qq $reqs >/dev/null
        ;;
     *)
	printf "bummer\n"
        ;;
esac

# install puppet agent
read -r -p "[1] To automate the on-boarding process to the plattform, the puppet agent will be installed (and removed afterwards)? [Y/n]" PUPPET
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
read -r -p "[2] Request a token from the idling.host API and create a certificate-signing-request to the certificate authortiy. Continue? [Y/n]" CSR
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
read -r -p "[3] Expose system metrics to the plattform for scheduling workloads responsibly? [Y/n]" METRICS
case "$METRICS" in
    [yY][eE][sS]|[yY])
        printf "downloading prometheus node exporter. running and exposing it on port 9100. Remember to allow access from prometheus.idling.host / IP: \n"
        dig +short prometheus.idling.host
        /opt/puppetlabs/puppet/bin/puppet resource package prometheus-node-exporter ensure=present
        /opt/puppetlabs/puppet/bin/puppet resource service prometheus-node-exporter ensure=running enable=true
        # exporting resource to puppetdb or ping api?
        ;;
     *)
        printf "bummer\n"
        ;;
esac


# Choose workload type (docker, pure binary)
printf "[4] How should the computing be deployed onto your node? \n"
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

# Run workload and earn money $$$
