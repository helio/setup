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

# directories
puppetpath="/etc/puppetlabs/puppet"
puppetbin="/opt/puppetlabs/puppet/bin/"

# files
csr_attributes="$puppetpath/csr_attributes.yaml"
puppet="$puppetbin/puppet"

# pass options to the script
while getopts t:m: option
do
case "${option}" in
    t) token=${OPTARG};;
    m) mail=${OPTARG};;
esac
done

# check if package exists
pkg_exists() {
    lsb_dist=$(get_distribution)
    case "$lsb_dist" in
        debian|ubuntu)
            dpkg --get-selections | grep -q "^$1[[:space:]]*install$" >/dev/null 2>&1
        ;;
        centos|redhat)
            return 0 # TODO add fast check for centos
        ;;
    esac
}

# check if command exists
command_exists() {
	command -v "$@" > /dev/null 2>&1
}

# check if file exists
file_exists() {
    if [ -f "$1" ]
    then
        return 0
    else
        return 1
    fi
}

# run curl with json data ($1) and target url ($2) and get http status
curl_status() {
    json="$1"
    url="$2"
    status=$(curl -s -o /dev/null -X POST -H "Content-Type: application/json" -d '{'$json'}' -w "%{http_code}" $url)
    echo $status
}

# run curl with json data ($1) and target url ($2) and get response
curl_response() {
    json="$1"
    url="$2"
    response=$(curl -fsSL -X POST -H "Content-Type: application/json" -d '{'$json'}' $url)
    echo "$response"
}

# resolve fqdn of the host
get_fqdn() {
    fqdn=$($puppet facts |jq '.values .fqdn')
    echo "$fqdn"
}
# check operating system
get_distribution() {
	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	echo "$lsb_dist"
}

# required packages
get_packages() {
    lsb_dist=$(get_distribution)
    case "$lsb_dist" in
        debian|ubuntu)
            pkg="apt-transport-https ca-certificates curl lsb-release dnsutils jq"
        ;;
        centos|redhat)
            pkg="ca-certificates curl redhat-lsb-core epel-release bind-utils jq"
        ;;
    esac
}

# join new server to users cluster
join_cluster() {
    token="$@"
    # get hostname
    fqdn=$(get_fqdn)
    # json data to send
    json="\"fqdn\":$fqdn,\"token\":\"$token\""

    # get jwt for csr attributes
    if file_exists $csr_attributes; then
        printf "$csr_attributes already exists. please delete"
    else
        csrtoken=$(curl_response $json $join |jq -r '.token')
        printf "custom_attributes:\n  challengePassword: \"$csrtoken\"" >> $csr_attributes
    fi

    # configure puppet
    if file_exists $puppet; then
        $puppet config set certname $fqdn
        $puppet config set use_srv_records true
        $puppet config set srv_domain idling.host
        $puppet config set environment setupscript --section agent
    else
        printf "puppet binary doesnt exists, please check package installation"
    fi
}

# register new user
register_user() {
    mail="$1"

    # get hostname
    fqdn=$(get_fqdn)

    # json data to send
    json="\"fqdn\":$fqdn,\"email\":\"$mail\""

    # register user
    curl_response $json $register
    printf "Please check your Inbox and confirm the link"
}

register_ping() {
    mail="$1"

    # get hostname
    fqdn=$(get_fqdn)

    # json data to send
    json="\"fqdn\":$fqdn,\"email\":\"$mail\""

    while true
    do
        # loop until mail is confirmed / yay, DOSing our API
        status=$(curl_status $json $register_ping)

        if [ "${status}" -eq 416 ]; then
            break
        else
            sleep 10;
        fi
   done
}

# Platform detection
# Distribution
lsb_dist=$(get_distribution)
lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

# Release version
if command_exists lsb_release; then
    case "$lsb_dist" in
        debian|ubuntu)
            dist_version="$(lsb_release -cs)"
        ;;
        centos)
            dist_version="$(lsb_release -rs|cut -c1)"
        ;;
    esac
fi

# check for conflics
read -r -p "[0] Checking for conflicts [Y/n]" CHECK
case "$CHECK" in
    [yY][eE][sS]|[yY])
        msg="WARNING: puppet is already installed, only continue if it's OK to overwrite settings \n"
        if command_exists puppet; then
            printf "$msg"
        fi
        if file_exists $puppet; then
            printf "$msg"
        fi
        if [ "$user" != 'root' ]; then
            if command_exists sudo; then
                #TODO: support sudo / su
                sh_c='sudo -E sh -c'
            elif command_exists su; then
                sh_c='su -c'
            else
		    	printf "Error: this installer needs the ability to run commands as root. We are unable to find either "sudo" or "su" available to make this happen."
			    exit 1
            fi
        fi
        ;;
    *)
        # no action, next step
        ;;
esac


# install required packages
get_packages
read -r -p "[1] The following packages and dependencies are going to be installed: $pkg [Y/n]" PACKAGE
case "$PACKAGE" in
    [yY][eE][sS]|[yY])
        # check if already installed
        if pkg_exists $pkg; then
            echo "already installed"
        else
            printf "installing packages\n"
            case "$lsb_dist" in
                debian|ubuntu)
                    apt-get update -qq >/dev/null
                    apt-get install -y -qq $pkg >/dev/null
                    ;;
                centos|redhat)
                    #yum check-update -q >/dev/null TODO: fix exit codes
                    yum install -y -q $pkg >/dev/null
                    ;;
            esac
        fi
        ;;
     *)
        printf "Can't continue. Exiting"
        exit 1;
        ;;
esac

# install puppet agent based os release
read -r -p "[2] To automate the on-boarding process to the plattform, the puppet agent will be installed (and removed afterwards)? [Y/n]" PUPPET
case "$PUPPET" in
    [yY][eE][sS]|[yY])
        # check if already installed
        if pkg_exists puppet-agent; then
            echo "already installed"
        else
            printf "installing puppet\n"
            case "$lsb_dist" in
                debian|ubuntu)
                    curl -sLO https://apt.puppetlabs.com/puppet5-release-$dist_version.deb -o /tmp/puppet5-release-$dist_version.deb
                    dpkg -i puppet5-release-$dist_version.deb
                    apt-get update -qq >/dev/null
                    apt-get install -y -qq puppet-agent >/dev/null
                    ;;
                centos|redhat)
                    rpm -Uvh https://yum.puppet.com/puppet5/puppet5-release-el-$dist_version.noarch.rpm
                    yum install -y -q puppet-agent  >/dev/null
                    ,,
                esac
        fi
        ;;
     *)
        printf "Can't continue. Exiting"
        exit 1;
        ;;
esac

# new user or new server?
read -r -p "[3] Do you already have an account at idling.host? [Y/n]" start
case "$start" in
    [yY][eE][sS]|[yY])
        # join cluster with a new server by token
        if [ -z $token ]; then
            printf "Please enter your token to on-board the node to the cluster.\n"
            read -r -p "Your token: " token
        fi
        if join_cluster $token; then
            printf "Cluster joined"
        fi
        ;;
    *)
        # on-board user (email, hostname)
        if [ -z $mail ]; then
            printf "Please enter your mail and connect / register your account.\n"
            read -r -p "Mail: " mail
        fi

        # register user with mail
        register_user $mail

        # check if mail is confirmed
        uid=$(register_ping $mail)

        # join cluster with a new server by token
        if [ -z $token ]; then
            printf "Please enter your token to on-board the node to the cluster.\n"
            read -r -p "Your token: " token
        fi
        if join_cluster $token; then
            printf "Cluster joined"
        fi
        ;;
esac

# Export metrics to our backend
read -r -p "[4] Expose system metrics to the plattform for scheduling workloads responsibly? [Y/n]" METRICS
case "$METRICS" in
    [yY][eE][sS]|[yY])
        printf "downloading prometheus node exporter. running and exposing it on port 9100. Remember to allow access from metrics.idling.host / IP: \n"
        dig +short metrics.idling.host
        $puppet resource package prometheus-node-exporter ensure=present
        $puppet resource service prometheus-node-exporter ensure=running enable=true
        # TODO: exporting resource to puppetdb or ping api?
        ;;
     *)
         # no action, contiunue
        ;;
esac


# Choose workload type (docker, pure binary)
printf "[5] How should the computing be deployed onto your node? \n"
read -r -p "Choose 0 [Docker] 1 [Kubernetes] 2 [Service] 9 [Stop]" WORKLOAD
case "$WORKLOAD" in
    [0])
        echo "Going to install Docker"
        $puppet agent -t && $puppet agent -t
        ;;
    [1])
        echo "Option not available yet"
        ;;
    [2])
        echo "Option not available yet"
        ;;
    *)
        printf "ok, bye ;-( \n"
        ;;
 esac

# Run workload and earn money $$$
