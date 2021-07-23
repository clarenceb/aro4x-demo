Firewall
========

Reference: https://docs.microsoft.com/en-us/azure/openshift/howto-restrict-egress

Continuing on from the setup used in this demo.  Let's configure egress lockdown with an Azure Firewall.
We'll create a dedicated subnet for the Azure Firewall in our utils VNET (rather than the ARO VNET).

```sh
source ../aro4-env.sh

# Create the Firewall's subnet
az network vnet subnet create \
    -g "$RESOURCEGROUP" \
    --vnet-name "$UTILS_VNET" \
    -n "AzureFirewallSubnet" \
    --address-prefixes 10.0.6.0/24

# Create the public IP for the Firewall
az network public-ip create -g $RESOURCEGROUP -n fw-ip --sku "Standard" --location $LOCATION

# Install extension to manage Azure Firewall from Azure CLI
az extension add -n azure-firewall
az extension update -n azure-firewall

# Create the actual firewall and configure its public facing IP.
az network firewall create -g $RESOURCEGROUP -n aro-private -l $LOCATION
az network firewall ip-config create -g $RESOURCEGROUP -f aro-private -n fw-config --public-ip-address fw-ip --vnet-name "$UTILS_VNET"

FWPUBLIC_IP=$(az network public-ip show -g $RESOURCEGROUP -n fw-ip --query "ipAddress" -o tsv)
FWPRIVATE_IP=$(az network firewall show -g $RESOURCEGROUP -n aro-private --query "ipConfigurations[0].privateIpAddress" -o tsv)

echo $FWPUBLIC_IP
echo $FWPRIVATE_IP

# Get the id for the ARO VNET.
vNet1Id=$(az network vnet show \
  --resource-group $RESOURCEGROUP \
  --name $VNET \
  --query id --out tsv)

# Get the id for the Utils VNET.
vNet2Id=$(az network vnet show \
  --resource-group $RESOURCEGROUP \
  --name $UTILS_VNET \
  --query id \
  --out tsv)

# Peer ARO VNET with the Utils VNET
az network vnet peering create \
  --name aroVnet-utilsVnet \
  --resource-group $RESOURCEGROUP \
  --vnet-name $VNET \
  --remote-vnet $vNet2Id \
  --allow-vnet-access

# Peer Utils VNET with the ARO VNET
az network vnet peering create \
  --name utilsVnet-aroVnet \
  --resource-group $RESOURCEGROUP \
  --vnet-name $UTILS_VNET \
  --remote-vnet $vNet1Id \
  --allow-vnet-access

# Verify the peering is in place
az network vnet peering show \
  --name aroVnet-utilsVnet \
  --resource-group $RESOURCEGROUP \
  --vnet-name $VNET \
  --query peeringState

# Create a UDR and Routing Table for Azure Firewall
az network route-table create -g $RESOURCEGROUP --name aro-udr
az network route-table route create -g $RESOURCEGROUP --name aro-udr --route-table-name aro-udr --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address $FWPRIVATE_IP
```

Application rules for ARO to work based on this [list](https://docs.openshift.com/container-platform/4.6/installing/install_config/configuring-firewall.html#configuring-firewall_configuring-firewall):

```sh
az network firewall application-rule create -g $RESOURCEGROUP -f aro-private \
 --collection-name 'ARO' \
 --action allow \
 --priority 100 \
 -n 'required' \
 --source-addresses '*' \
 --protocols 'http=80' 'https=443' \
 --target-fqdns 'registry.redhat.io' '*.quay.io' 'sso.redhat.com' 'management.azure.com' 'mirror.openshift.com' 'api.openshift.com' 'quay.io' '*.blob.core.windows.net' 'gcs.prod.monitoring.core.windows.net' 'registry.access.redhat.com' 'login.microsoftonline.com' '*.servicebus.windows.net' '*.table.core.windows.net' 'grafana.com'
```

Optional rules for Docker images:

```sh
az network firewall application-rule create -g $RESOURCEGROUP -f aro-private \
 --collection-name 'Docker' \
 --action allow \
 --priority 200 \
 -n 'docker' \
 --source-addresses '*' \
 --protocols 'http=80' 'https=443' \
 --target-fqdns '*cloudflare.docker.com' '*registry-1.docker.io' 'apt.dockerproject.org' 'auth.docker.io'
 ```

Test egress connectivity from ARO (before applying egress FW):

```sh
oc create ns test
oc apply -f firewall/egress-test-pod.yaml -n test
oc exec -it centos -n test -- /bin/bash
curl -i https://www.microsoft.com/
#HTTP/2 200
# ...
```

Associate ARO subnets to FW:

```sh
az network vnet subnet update -g $RESOURCEGROUP --vnet-name $VNET --name "master-subnet" --route-table aro-udr
az network vnet subnet update -g $RESOURCEGROUP --vnet-name $VNET --name "worker-subnet" --route-table aro-udr
```

Test egress connectivity (after applying egress FW)::

```sh
# Re-use the existing running centos container
oc exec -it centos -- /bin/bash
curl -i https://www.microsoft.com/
# curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to www.microsoft.com:443
curl -i  https://grafana.com
# HTTP/2 200
# ...
```

If you have enabled Diagnostic settings on the Firewall and enabled `AzureFirewallApplicationRule` to be logged, you can see the egress attempt and deny log by clicking on the firewall **Logs** pane and entering this sample query:

```sh
AzureDiagnostics
| where msg_s contains "Action: Deny"
| where  msg_s contains "microsoft"
| limit 10
| order by TimeGenerated desc
| project TimeGenerated, ResourceGroup, msg_s

# msg_s HTTPS request from x.x.x.x:yyyyyy to www.microsoft.com:443. Action: Deny. No rule matched. Proceeding with default action
```

(Optional) Setup ingress via FW for private OpenShift routes:

```sh
ROUTE_LB_IP=x.x.x.x

az network firewall nat-rule create -g $RESOURCEGROUP -f aro-private \
 --collection-name 'http-aro-ingress' \
 --priority 100 \
 --action 'Dnat' \
 -n 'http-ingress' \
 --source-addresses '*' \
 --destination-address $FWPUBLIC_IP \
 --destination-ports '80' \
 --translated-address $ROUTE_LB_IP \
 --translated-port '80' \
 --protocols 'TCP'
```

Clean-up:

```sh
# Delete test pod
oc delete -f firewall/egress-test-pod.yaml
```
