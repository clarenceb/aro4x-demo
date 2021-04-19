Cluster Logging
===============

Setup a Syslog server to test log forwarding:

```sh
source ../aro4-env.sh
az group create --name $RESOURCEGROUP --location $LOCATION

ssh-keygen -t rsa -b 2048 -C "syslog server" -f ./syslog-ssh-rsa -N ""

az vm create \
  --resource-group $RESOURCEGROUP \
  --name syslog-server \
  --image CentOS \
  --size Standard_D2s_v3 \
  --admin-username azureuser \
  --ssh-key-values ./syslog-ssh-rsa.pub \
  --public-ip-address "" \
  --vnet-name $UTILS_VNET \
  --subnet utils-hosts

az vm open-port --port 514 --resource-group $RESOURCEGROUP --name syslog-server
az vm list-ip-addresses --resource-group $RESOURCEGROUP --name syslog-server --query [].virtualMachine.network.privateIpAddresses[0] -o tsv

# Create a private DNS zone, link that to your utils-vnet VNET and add your VM IP address as an A record in the private zone.
# See:
# - https://docs.microsoft.com/en-us/azure/dns/private-dns-getstarted-cli#create-a-private-dns-zone

# Connect to the VM with your Bastion service, using the private key `./syslog-ssh-rsa`

sudo yum update -y
sudo yum -y install rsyslog
sudo systemctl status rsyslog.service
sudo systemctl enable rsyslog.service

echo "test message from user root" | logger
sudo tail /var/log/messages

sudo vi /etc/rsyslog.conf
# Uncomment lines below `Provides UDP syslog reception
```

```txt
# Provides TCP syslog reception
$ModLoad imtcp
$InputTCPServerRun 514
```

Save changes and exit `vi`.

```sh
sudo systemctl restart rsyslog
sudo netstat -antup | grep 514
```

Access the ARO console.

Go to the Operator Hub and install the "Cluster Logging" operator.

Select "Cluster Log Forwarder" and click "Create ClusterLogForwarder".

Refer to the docs for [Forwarding logs using the syslog protocol](https://docs.openshift.com/container-platform/4.6/logging/cluster-logging-external.html#cluster-logging-collector-log-forward-syslog_cluster-logging-external).

Example `ClusterLogForwarder` file (`syslog-forwarder.yaml`) to forward logs to the Syslog Server VM:

```yaml
apiVersion: logging.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance 
  namespace: openshift-logging 
spec:
  outputs:
    - name: syslog-server-vm
      syslog:
        facility: local0
        rfc: RFC5424
        severity: debug # switch to say `error` or `informational` later
      type: syslog
      url: 'tcp://<syslog-server-fqdn>:514'
  pipelines:
    - inputRefs:
        - application
        - infrastructure
        - audit
      labels:
        syslog: logforwarder-demo
      name: syslog-aro
      outputRefs:
        - syslog-server-vm
        - default
```

```sh
oc create -f syslog-forwarder.yaml
```

(Optional) Create Elasticsearch and Kibana for local log reception (`cluster-logging.yaml`):

```yaml
apiVersion: logging.openshift.io/v1
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  managementState: Managed
  logStore:
      elasticsearch:
        nodeCount: 3
        proxy:
          resources:
            limits:
              memory: 256Mi
            requests:
              memory: 256Mi
        redundancyPolicy: ZeroRedundancy
        resources:
          requests:
            memory: 2Gi
        storage:
          size: 50G
          storageClassName: managed-premium
      retentionPolicy:
        application:
          maxAge: 1d
        audit:
          maxAge: 7d
        infra:
          maxAge: 7d
      type: elasticsearch
  visualization:
    kibana:
      replicas: 1
    type: kibana
  collection:
    logs:
      fluentd: {}
      type: fluentd
  curation:
    curator:
      schedule: 30 3 * * *
    type: curator
```

```sh
oc create -f cluster-logging.yaml
```

Generate some logs from a container in ARO:

```sh
oc new-project test
oc run -it baseos --image centos:latest

[root@baseos /]# echo "this is a test"
[root@baseos /]# exit

oc delete pod/baseos
oc delete project test
```

Check the logs with "this is a test" appear in Kibana (create and select the "app-*" index filter).
Check the logs in the syslog server (tail output).

(Optional) Stop the Syslog Server VM:

```sh
az vm stop --resource-group $RESOURCEGROUP --name syslog-server
```

TODO
----

* Update steps to use CLI instead or Azure Portal and ARO console.

Resources
---------

* https://www.itzgeek.com/how-tos/linux/centos-how-tos/setup-syslog-server-on-centos-7-rhel-7.html
* https://docs.openshift.com/container-platform/4.6/logging/cluster-logging-external.html#cluster-logging-collector-log-forward-syslog_cluster-logging-external
