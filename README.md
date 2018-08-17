# Idling host setup script

## TL;DR

```shell
curl -fsSL un.idling.host -o start-computing.sh
if shasum -a 1 -s -c <(echo '35e6d88ed099d5c7fb1e91288e95dd8842e81af8 start-computing.sh'); then
    ./start-computing.sh
fi
```
## Introduction

This `/bin/sh` helps you to join idling.host as a supplier, prepares your system and make the computing power available on our market.
You can watch your metrics and stop / start the computing always on panel.idling.host.
There you also see how much money you've earned and the CO2 emissions you've saved.


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
| curl            | download scrip, communicate with API | all             |
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

## Choria

The choria go binary Connects your node to our broker, to receive tasks and orchestrate workloads.
The communication is fully secured by TLS, including user authentification.
We provision your node and make the following tasks available for our broker / backend:

* facts (get system information)
* docker swarm: join, leave
* TBD

The choria server is only pulling the information from our broker and pushes the answer / output of the task.
You can always stop / remove the service and disable our access to the mention functions:

`service choria stop`
`apt-get remove choria`

## Firewall
For a functional setup, the following protocols and connections should be allowed to your node(s).

### Incoming

| Host  / Port                | usage                                                |
| :-------------------------- |:---------------------------------------------------- |
| prometheus.idling.host:9100 | allow Prometheus to collect metrics from your server |

### Outgoing

This includes incoming pakets / answers for established connections.

| Host  / Port            | protocol     | usage        |
| :---------------------- |:------------ | :----------- |
| broker.idling.host:4222 | TCP          | get tasks from our broker |
| wildcard:7964           | TCP and UDP  | communication between our swarm nodes |
| wildcard:4789           | UDP          | overlay network|
| wildcard:50             | custom (ESP) | encrypt overlay traffic |
