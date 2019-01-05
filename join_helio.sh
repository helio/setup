#!/bin/sh
set -e

# This script is meant for quick & easy install via:
#   $ curl -fsSL un.idling.host -o start-computing.sh
#   $ sh start-computing.sh
#
# install script to join the Helio Cloud

# TODO: script SHA, changed during upload / deploy
SCRIPT_COMMIT_SHA=321120a4347749dc9348b0db4039fec327dff651

# our API endpoints
base="https://panel.idling.host"
register="$base/server/init"
register_ping="$base/server/init"
gettoken="$base/server/gettoken"
join="$base/server/register"

# directories
puppetpath="/etc/puppetlabs/puppet"
puppetbin="/opt/puppetlabs/puppet/bin"
facter="/etc/facter/facts.d/"

# files
csr_attributes="$puppetpath/csr_attributes.yaml"
ssl_dir="$puppetpath/ssl"
certificates="$ssl_dir/private_keys"
puppet="$puppetbin/puppet"
user_json="$facter/user.json"

# support
mail="support@helio.exchange"
exit="Can not proceed, please contact our support at $mail or run again. Exiting..."

# help message
usage="$(basename "$0") [-h] [-v] [-a] [-t yourtoken] [-m yourmail] [-l ultimatequestion]
where:
    -h shows this help
    -v enable verbose mode
    -a enable auto setup (no questions asked)
    -t set Helio panel token as argument
    -g enable GCP mode, get token from metadata
    -m set your user email as argument
    -l Answer to the Ultimate Question of Life, the Universe, and Everything"

# pass options to the script
# use getopts and don't support long tail options
while getopts 'hvagt:m:l:' option; do
  case "${option}" in
    t) token=${OPTARG};;
    m) mail=${OPTARG};;
    v) verbose=1;;
    a) auto=1;;
    g) gcp=1;;
    l) echo "42"
       exit 1
       ;;
    h) echo "$usage"
       exit 1
       ;;
  esac
done

# set env var for puppet
export LC_ALL=C

# check if one package is installed (loop array)
pkg_exists() {
    lsb_dist=$(get_distribution)
    installed=$1
    case "$lsb_dist" in
        debian|ubuntu)
            dpkg --get-selections | grep -q "^$installed[[:space:]]*install$" >/dev/null 2>&1
        ;;
        centos|rhel)
            rpm -qa | grep -q $installed
        ;;
    esac
}

# install packages, if they don't exist
pkg_install() {
    lsb_dist=$(get_distribution)
    pkg=$@
    case "$lsb_dist" in
        debian|ubuntu)
            # check if installed
            if installed=$(dpkg --get-selections | grep -q "^$pkg[[:space:]]*install$" >/dev/null 2>&1); then
                printf "packages already installed, continue\n"
            else
                printf "installing packages $pkg\n"
                apt-get update -qq >/dev/null
                apt-get install -y -qq $pkg >/dev/null
            fi
            ;;
        centos|rhel)
            printf "installing packages $pkg\n"
             #yum check-update -q >/dev/null TODO: fix exit codes
            yum install -y -q $pkg >/dev/null
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

# check if directory exists
dir_exists() {
    if [ -d "$1" ]
    then
        return 0
    else
        return 1
    fi
}

# find files in a dir
find_files() {
    find $1 -type f 2>&1 | grep -v "No such file or directory"
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

# run curl with specified headers and parse answer from target url ($2)
curl_headers() {
    headers="$1"
    url="$2"
    response=$(curl -fsSL -X POST -H "$headers" $url)
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
        centos|rhel)
            pkg="ca-certificates curl redhat-lsb-core epel-release bind-utils jq"
        ;;
    esac
}

# join new server / nodes to the Helio Cloud
join_helio() {
    token="$@"
    # get hostname
    fqdn=$(get_fqdn)
    # json data to send
    json="\"fqdn\":$fqdn,\"token\":\"$token\""

    # get jwt for csr attributes
    if file_exists $csr_attributes; then
        read -p "File $csr_attributes exists. Do you want to delete? [y/n] " delete
        case "$delete" in
            [yY][eE][sS]|[yY])
                rm $csr_attributes
                ;;
            *)
                printf "need to cleanup, please remove $csr_attributes  manually and start again"
                exit 1
                ;;
        esac
    fi

    # get response and write csr token
    response=$(curl_response $json $join)
    csrtoken=$(echo "$response"|jq -r '.token' 2> /dev/null)
    printf "custom_attributes:\n  challengePassword: \"$csrtoken\"" >> $csr_attributes

    # write response data userid and serverid into json for facter
    if dir_exists $facter; then
        echo "$response"|jq '. | {user_id: .user_id, server_id: .server_id}' -M 2> /dev/null > $user_json
    else
        mkdir -p $facter
        echo "$response"|jq '. | {user_id: .user_id, server_id: .server_id}' -M 2> /dev/null > $user_json
    fi

    # configure puppet
    if file_exists $puppet; then
        $puppet config set certname $fqdn
        $puppet config set use_srv_records true
        $puppet config set srv_domain idling.host
        $puppet config set environment setupscript --section agent
    else
        printf "puppet binary doesnt exists, please check package installation\n"
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
    printf "Please check your Inbox and confirm the link\n"
}

# Ping API to check if mail is confirmed
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

## Platform detection
# Distribution
lsb_dist=$(get_distribution)
lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

# Release version
dist_version() {
    if command_exists lsb_release; then
        case "$lsb_dist" in
            debian|ubuntu)
                dist_version="$(lsb_release -cs)"
                ;;
            centos|rhel)
                dist_version="$(lsb_release -rs|cut -c1)"
                ;;
        esac
    fi
}

# auto mode enabled?
if [ -z "$auto" ]; then
    read -r -p "[0] Checking for conflicts [Y/n]" CHECK
else
    CHECK=y
fi

# check for conflicts
case "$CHECK" in
    [yY][eE][sS]|[yY])
        msg="WARNING: puppet is already installed, only continue if it's OK to overwrite settings\n"
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
		    	printf "Error: this installer needs the ability to run commands as root. We are unable to find either "sudo" or "su" available to make this happen.\n"
			    exit 1
            fi
        fi
        ;;
    *)
        # no action, next step
        ;;
esac

# auto mode enabled?
get_packages
if [ -z "$auto" ]; then
    read -r -p "[1] The following packages and dependencies are going to be installed: $pkg [Y/n]" PACKAGE
else
    PACKAGE=y
fi

# install required packages
case "$PACKAGE" in
    [yY][eE][sS]|[yY])
        # check if package installed, if not install
        if pkg_install $pkg; then
            echo "packages $pkg installed"
        else
            echo "error, please check $pkg installation"
        fi
        ;;
     *)
        printf "$exit"
        exit 1;
        ;;
esac

# auto mode enabled?
if [ -z "$auto" ]; then
    read -r -p "[2] To automate the on-boarding process to the platform, the puppet agent will be installed? [Y/n]" PUPPET
else
    PUPPET=y
fi

# install puppet agent based os release
dist_version
case "$PUPPET" in
    [yY][eE][sS]|[yY])
            case "$lsb_dist" in
                debian|ubuntu)
                    # puppet release repo
                    if pkg_exists puppet6-release; then
                        printf "puppet6 release repo already installed\n"
                    else
                        if [ -z "$verbose" ]; then
                            curl -sLO https://apt.puppetlabs.com/puppet6-release-$dist_version.deb -o /tmp/puppet6-release-$dist_version.deb
                            dpkg -i puppet6-release-$dist_version.deb &>/dev/null
                            sleep 3
                        else
                            curl -sLO https://apt.puppetlabs.com/puppet6-release-$dist_version.deb -o /tmp/puppet6-release-$dist_version.deb
                            dpkg -i puppet6-release-$dist_version.deb
                            sleep 3
                        fi

                    fi
                    #puppet agent
                    if pkg_exists puppet-agent; then
                        printf "puppet agent already installed\n"
                    else
                        pkg_install puppet-agent
                    fi
                    ;;
                centos|rhel)
                    # puppet release repo
                    if pkg_exists puppet6-release; then
                        printf "puppet6 release repo already installed\n"
                    else
                        # install puppet6 repo from url
                        rpm -Uvh https://yum.puppet.com/puppet6/puppet6-release-el-$dist_version.noarch.rpm
                    fi
                    # puppet agent
                    if pkg_exists puppet-agent; then
                        printf "puppet agent already installed\n"
                    else
                        pkg_install puppet-agent
                    fi
                    ;;
            esac
            # check if certificates already exist
            if find_files $certificates; then
                read -p "Puppet private keys already exists on your system. Do you already use puppet for other things? [y/n] " ask
                case "$ask" in
                    [yY][eE][sS]|[yY])
                        printf "Please contact our support at $mail. Exiting..."
                        exit 1
                        ;;
                    *)
                        read -p "The directory $ssl_dir exists - probably from previews script runs. Do you want to delete it? [y/n] " delete
                        case "$delete" in
                            [yY][eE][sS]|[yY])
                                rm -ir $ssl_dir
                                printf "Probably you need to remove your server from panel.idling.host first, to create a new CSR"
                                ;;
                            *)
                                printf "$exit"
                                exit 1
                                ;;
                        esac
                        ;;
                esac
            fi
            ;;
        *)
            # dont proceed with puppet, exit
            printf "$exit"
            exit 1;
            ;;
    esac

# auto mode enabled?
if [ -z "$auto" ]; then
    read -r -p "[3] Do you already have an account at idling.host? [Y/n]" START
else
    START=y
fi

# check for GCP mode
# overwrite token with metadata token
if [ -n "$gcp" ]; then
  header= "Metadata-Flavor: Google"
  metadata_url="http://metadata.google.internal/computeMetadata/v1/instance/attributes/helio/"
  token=$(curl_headers $header $metadata_url)
fi

# new user or new server?
case "$START" in
    [yY][eE][sS]|[yY])
        # join Helio with a new server by token
        if [ -z $token ]; then
            printf "Please enter your token from panel.idling.host to on-board the node to the Helio Cloud.\n"
            read -r -p "Your token: " token
        fi
        if join_helio $token; then
            printf "Node verified and authenticated.\n"
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

        # join Helio with a new server by token
        if [ -z $token ]; then
            printf "Please enter your token from panel.idling.host to on-board the node to the Helio Cloud.\n"
            read -r -p "Your token: " token
        fi
        if join_helio $token; then
            printf "Node verified and authenticated.\n"
        fi
        ;;
esac

# auto mode enabled?
if [ -z "$auto" ]; then
    read -r -p "[4] Expose system metrics to the plattform for scheduling workloads responsibly? [Y/n]" METRICS
else
    METRICS=y
fi

# Export metrics to our backend
case "$METRICS" in
    [yY][eE][sS]|[yY])
        lsb_dist=$(get_distribution)
        case "$lsb_dist" in
            debian|ubuntu)
                printf "downloading prometheus node exporter. running and exposing it on port 9100. Remember to allow access from metrics.idling.host / IP: \n"
                dig +short metrics.idling.host
                $puppet resource package prometheus-node-exporter ensure=present
                $puppet resource service prometheus-node-exporter ensure=running enable=true
                ;;
            centos|rhel)
                printf "metrics not supported yet\n" #TODO add rpm in our repo for node exporter
                ;;
        esac
        ;;
     *)
         # no action, continue
        ;;
esac

# auto mode enabled?
# use Docker as default. TODO improve later
if [ -z "$auto" ]; then
    printf "[5] How should the computing be deployed onto your node? \n"
    read -r -p "Choose 0 [Docker] 1 [Kubernetes] 2 [Service] 9 [Stop]" WORKLOAD
else
    WORKLOAD=0
fi

# Choose workload type (docker, pure binary)
case "$WORKLOAD" in
    [0])
        # check for docker installation source script: https://get.docker.com/
        if command_exists docker; then
        cat >&2 <<-'EOF'
        Warning: the "docker" command appears to already exist on this system.

		If you already have Docker installed, this script can cause trouble, which is
	    why we're displaying this warning and provide the opportunity to cancel the
		installation.

	    You may press Ctrl+C now to abort this script.
		EOF
        ( set -x; sleep 20 )
        fi


        # run puppet
        if [ -z "$verbose" ]; then
            printf "Joining the Helio Cloud and configure system. Setup takes up to 5 minutes. Stay tuned. \n"
            $puppet agent && $puppet agent
        else
            printf "Joining the Helio Cloud and configure system in the background. Setup takes up to 5 minutes. Stay tuned. \n"
            $puppet agent -t && $puppet agent -t
        fi
        ;;
    [1])
        echo "Option not available yet. Please choose Docker.\n"
        ;;
    [2])
        echo "Option not available yet. Please choose Docker.\n"
        ;;
    *)
        printf "ok, bye ;-( \n"
        ;;
 esac

# Run complete
printf "[6] Script run complete. Check panel.idling.host later for node status and success. Thanks\n"
# TODO: create /api/status and check setup status
