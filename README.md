# Idling host setup script

## TL;DR

```shell
curl -fsSL un.idling.host -o start-computing.sh
if shasum -a 1 -s -c <(echo '35e6d88ed099d5c7fb1e91288e95dd8842e81af8 start-computing.sh'); then
    sh start-computing.sh
fi
```

`start-computing.sh` options:
 * -h shows this help
 * -v enable verbose mode
 * -a enable auto setup (no questions asked)
 * -t set Helio panel token as argument
 * -m set your users email as argument

### Example for auto-joining:
Requires an existing account and a token.

```shell
curl -fsSL un.idling.host -o start-computing.sh
if shasum -a 1 -s -c <(echo '35e6d88ed099d5c7fb1e91288e95dd8842e81af8 start-computing.sh'); then
    sh start-computing.sh -m your@mail.com -t 6b4123cb:f33b1a4b1c22d7ac9dab0ab759a38584d0d2506b -a
fi
```

## Introduction

This `/bin/sh` automates the process of joining the idling.host platform. It prepares your system and makes the computing power available on our market.
You can watch the metrics and stop / start the computing always on [panel.idling.host](https://panel.idling.host)

Outlook: In the future, you can also track e.g. how much money you've earned and the CO2 emissions you've saved.

## Setup steps

You need to create an account for our platform. It's possible to create an account during script execution or on our website [panel.idling.host](https://panel.idling.host).
*Pro mode: Use -m yourmail@domain.com during script execution and confirm the welcome mail in your mailbox*

Every server needs to be verified and assigned to your account by a token. You can create a token by adding your servername within the suppliers area.
*Pro mode: Use -t token during script execution*

## Supported OS

| OS            | Version         |
| ------------- |:----------------|
| Debian        | Jessie, Stretch |
| Ubuntu        | >= 16.04 LTS    |
| RHEL          | 6x, 7x          |
| CentOS        | 6x, 7x          |

## Installed / used components

### official OS packages

| Package         | usage                                | OS              |
| --------------- |:-------------------------------------|:--------------- |
| ca-certificates | validate TLS connections             | all             |
| curl            | download script, communicate with API| all             |
| dnsutils        | to dig the prometheus.idling.host ip | Debian & Ubuntu |
| epel-release    | repository                           | RHEL, CentOS    |
| jq              | lightweight parser for json          | all             |
| lsb-release     | resolve OS, version                  | Debian & Ubuntu |
| redhat-lsb-core | resolve OS, versio                   | RHEL, CentOS    |


### 3rd party modules

| Package                  | usage                                                                                  | OS  |
| :------------------------|:-------------------------------------------------------------------------------------- |:----|
| choria                   | push commands from our scheduler                                                       | all |
| docker-ce                | join our swarm, get computation tasks                                                  | all |
| puppet-agent             | create certificate, sign it from our CA, secure connections, system provisioning layer | all |
| prometheus-node-exporter | collect system metrics and expose them on port 9100                                    | all |

## Puppet Agent

This script is installing and configuring the `puppet-agent` from [Puppetlabs](https://github.com/puppetlabs/puppet).
The agent is used to create your clients certificate and let it sign from our certificate authority.
Your node is assigned to your account, secured by an additional certificate signing request (CSR) based on an unique JWT.

**important:** if your node is already puppet for another reason, please contact our support first.


## Choria

The choria go binary connects your node to our broker, to receive tasks and orchestrate the workloads.
The communication is fully secured by TLS, including user authentication.
We provision your node and make the following tasks available for our broker / backend:

* facts (get system information)
* docker swarm: join, leave

The choria server is only pulling the information from our broker and pushes the answer / output of the task.
You can always stop / remove the service and disable our access to the mention functions:

`service choria stop`

`apt-get remove choria`

## Docker CE worker

Ilding host is using [Docker](https://docker.com) to bring our customers workloads to your node.
This script will install and configure Docker, to work with our Docker Swarm.
Your node will act as Docker worker and will get computing jobs, managed by our Swarm manager nodes.
It will also create an encrypted network, to communicate with other Swarm nodes.


## Kubernetes worker

Additional Kubernetes support will follow soon. Stay tuned.

## Prometheus

Our system is collecting metrics from your system and store them on our [Prometheus](https://prometheus.io) cluster.
We need those metrics, to bring computing tasks to your system, if it's safe.
The metrics are also needed to calculate your contribution to our platform.
You'll be able to monitor those metrics in our [panel.idling.host](https://panel.idling.host). Yay, free monitoring.

## Firewall
For a functional setup, the following protocols and connections should be allowed to your node(s).

### Incoming

| Host  / Port                | usage                                                |
| :-------------------------- |:---------------------------------------------------- |
| prometheus.idling.host:9100 | allow Prometheus to collect metrics from your server |

### Outgoing

This includes incoming packets / answers for established connections.

| Host  / Port            | protocol     | usage        |
| :---------------------- |:------------ | :----------- |
| broker.idling.host:4222 | TCP          | get tasks from our broker |
| wildcard:7964           | TCP and UDP  | communication between our swarm nodes |
| wildcard:4789           | UDP          | overlay network|
| wildcard:50             | custom (ESP) | encrypt overlay traffic |
