#!/bin/sh
set -e

# This script is meant for quick & easy install via:
#   $ curl -fsSL un.idling.host -o start-computing.sh
#   $ sh start-computing.sh
#
# install script to join our cluster

# api endpoints
base="https://panel.idling.host/"
register="$base/server/init"
register_ping="$base/server/init"
gettoken="$base/server/gettoken"
join="$base/server/register"

# our default functions
command_exists() {
	command -v "$@" > /dev/null 2>&1
}

# TODO: add curl function
run_curl()

# check operating system
get_distribution() {
	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	echo "$lsb_dist"
}

# join new server to users cluster
join_cluster() {
    token="$@"
    # fire join api command
    csrtoken=$(curl -X POST -H "Content-Type: application/json" -d '{"fqdn":\"$fqdn\","email":\"$token\"}' $join| jq -r '.token')
    #TODO: parse possible json error messages
    printf "custom_attributes:\n  challengePassword: \"$csrtoken\"" >> /etc/puppetlabs/puppet/csr_attributes.yaml
    #TODO: first check if file exists
    /opt/puppetlabs/puppet/bin/puppet config set certname token.idling.host
    /opt/puppetlabs/puppet/bin/puppet config set use_srv_records true
    /opt/puppetlabs/puppet/bin/puppet config set srv_domain idling.host
    /opt/puppetlabs/puppet/bin/puppet config set environment setupscript --section agent
}

# register new user
register_user() {
    mail="$1"
    # get hostname
    fqdn=$(/opt/puppetlabs/bin/puppet facts |jq '.values .fqdn')
    # fire user register command
    status=$(curl -X POST -H "Content-Type: application/json" -d '{"fqdn":"'$fqdn'","email":"'$mail'"}' $register | jq -r '.status')
    printf "Please check your Inbox and confirm the link"
    # loop until mail is confirmed / yay, DOSing our API
    while [ "$status" != "416" ]
    do
        echo "Mail not confirmed yet. waiting 10s and try again"
        sleep 10;
        status=$(curl -X POST -H "Content-Type: application/json" -d '{"fqdn":"'$fqdn'","email":"'$mail'"}' $register_ping | jq -r '.status')
    done
    # request uid token to join cluster afterwards
    uidtoken=$(curl -X POST -H "Content-Type: application/json" -d '{"fqdn":"'$fqdn'","email":"'$mail'"}' $gettoken | jq -r '.token')
    echo "$uidtoken"
}

# supported & tested distros
DISTRO_MAP="
x86_64-debian-jessie
x86_64-debian-stretch
"

# required packages
reqs="apt-transport-https ca-certificates curl git lsb-release dnsutils jq"

# Platform detection
lsb_dist=$( get_distribution )
lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
case "$lsb_dist" in
    debian)
        dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
        case "$dist_version" in
			9)
				dist_version="stretch"
			;;
			8)
				dist_version="jessie"
			;;
			7)
				dist_version="wheezy"
			;;
		esac
	;;
esac

# check for conflics
# e.g. installed puppet
read -r -p "[0] Checking for conflicts [Y/n]" CHECK
case "$CHECK" in
    [yY][eE][sS]|[yY])
        if command_exists puppet; then
            printf "puppet is already installed, only continue if it's OK to overwrite settings \n"
        fi
        #TODO: show sucess message
        #TODO: also check for puppet file if command not available
        ;;
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
read -r -p "[1] The following packages and dependencies are going to be installed: $reqs [Y/n]" PACKAGE
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

# install puppet agent based os release

read -r -p "[2] To automate the on-boarding process to the plattform, the puppet agent will be installed (and removed afterwards)? [Y/n]" PUPPET
case "$PUPPET" in
    [yY][eE][sS]|[yY])
        printf "installing puppet\n"
	    curl -sLO https://apt.puppetlabs.com/puppet5-release-$dist_version.deb -o /tmp/puppet5-release-$dist_version.deb
	    dpkg -i puppet5-release-$dist_version.deb
	    apt-get update -qq >/dev/null
        apt-get install -y -qq puppet-agent >/dev/null
        ;;
     *)
	printf "bummer\n"
        ;;
esac

# new user or new server?
read -r -p "[3] Do you already have an account at idling.host? [Y/n]" start
case "$start" in
    [yY][eE][sS]|[yY])
        # join cluster with a new server by token
        # TODO: provide shell script cli param
        printf "Please enter your token to on-board the node to the cluster.\n"
        read -r -p "Your token: " uid
        if join_cluster uid; then
            printf "Cluster joined"
        fi
        ;;
    *)
        # on-board user (email, hostname)
        printf "Please enter your mail and connect / register your account.\n"
        read -r -p "Mail: " mail

        #use registration function and pass mail var
        uid=$(register_user mail)

        # join cluster
        if uid; then
            if join_cluster uid; then
                printf "Cluster joined"
            fi
        fi
        ;;
esac


# get JWT and create certificate & CSR
read -r -p "[4] Request a token from the idling.host API and create a certificate-signing-request to the certificate authortiy. Continue? [Y/n]" CSR
case "$CSR" in
    [yY][eE][sS]|[yY])
        ;;
     *)
	printf "bummer\n"
        ;;
esac


# Export metrics to our backend
read -r -p "[5] Expose system metrics to the plattform for scheduling workloads responsibly? [Y/n]" METRICS
case "$METRICS" in
    [yY][eE][sS]|[yY])
        printf "downloading prometheus node exporter. running and exposing it on port 9100. Remember to allow access from metrics.idling.host / IP: \n"
        dig +short metrics.idling.host
        /opt/puppetlabs/puppet/bin/puppet resource package prometheus-node-exporter ensure=present
        /opt/puppetlabs/puppet/bin/puppet resource service prometheus-node-exporter ensure=running enable=true
        # exporting resource to puppetdb or ping api?
        ;;
     *)
        printf "bummer\n"
        ;;
esac


# Choose workload type (docker, pure binary)
printf "[6] How should the computing be deployed onto your node? \n"
read -r -p "Choose 0 [Docker] 1 [Service] 2 [Stop]" WORKLOAD
case "$WORKLOAD" in
    [0])
        echo "Going to install Docker"
        /opt/puppetlabs/puppet/bin/puppet agent -t
        ;;
    [1])
        echo "Option not available yet"
        ;;
    [2])
        echo "bummer"
        ;;
    *)
        printf "bummer\n"
        ;;
 esac

# Run workload and earn money $$$
