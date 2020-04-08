Azure Red Hat OpenShift 4.3 (Private Preview)
=============================================

Follow steps here: https://docs.microsoft.com/en-us/azure/openshift/howto-using-azure-redhat-openshift

Prerequisites
-------------

* Install Azure CLI
* Install `az aro` extension
* Azure Tenant where you have [Global Administrator](https://docs.microsoft.com/en-us/azure/openshift/howto-create-tenant) access
* Cluster AAD application (client ID and secret) and service principal - [more info](https://docs.microsoft.com/en-us/azure/openshift/howto-aad-app-configuration)
* (Optional) `htpasswd` utility (Ubuntu: `sudo apt install apache2-utils -y`)

```sh
az provider register -n Microsoft.RedHatOpenShift --wait
az extension add -n aro --index https://az.aroapp.io/preview
```

Create Cluster
--------------

It normally takes about 35 minutes to create a cluster.

```sh
source ./aro43-env.sh

# Create resource group to hold cluster resources
az group create -g "${ARO_RESOURCEGROUP}" -l "${ARO_LOCATION}"

# Create the virtual network
az network vnet create \
  -g "${ARO_RESOURCEGROUP}" \
  -n "${ARO_VNET}" \
  --address-prefixes 10.0.0.0/9 \
  >/dev/null

# Add two empty subnets to your virtual network
for subnet in "${ARO_CLUSTER}-master" "${ARO_CLUSTER}-worker"; do
  az network vnet subnet create \
    -g "${ARO_RESOURCEGROUP}" \
    --vnet-name "${ARO_VNET}" \
    -n "$subnet" \
    --address-prefixes 10.$((RANDOM & 127)).$((RANDOM & 255)).0/24 \
    --service-endpoints Microsoft.ContainerRegistry \
    >/dev/null
done

# Disable network policies for Private Link Service on your virtual network and subnets.
# This is a requirement for the ARO service to access and manage the cluster.
az network vnet subnet update \
  -g "${ARO_RESOURCEGROUP}" \
  --vnet-name "${ARO_VNET}" \
  -n "${ARO_CLUSTER}-master" \
  --disable-private-link-service-network-policies true \
  >/dev/null

# Create the actual ARO cluster.
az aro create \
  -g "${ARO_RESOURCEGROUP}" \
  -n "${ARO_CLUSTER}" \
  --vnet "${ARO_VNET}" \
  --master-subnet "${ARO_CLUSTER}-master" \
  --worker-subnet "${ARO_CLUSTER}-worker"
```

Login to Web console (kubeadmin)
--------------------------------

```sh
# Get Console URL from command output
az aro list -o table
# URL = https://console-openshift-console.apps.<aro-domain>

# Get admin username and password (user is kubeadmin)
az aro list-credentials -g "${ARO_RESOURCEGROUP}" -n "${ARO_CLUSTER}"
```

Add Identity Provider for other users
-------------------------------------

Configure [HTPasswd](https://docs.openshift.com/container-platform/4.3/authentication/identity_providers/configuring-htpasswd-identity-provider.html) identity provider.

```sh
htpasswd -c -B -b aro-user.htpasswd user1 somepassword123
htpasswd -b $(pwd)/aro-user.htpasswd user2 somepassword456
htpasswd -b $(pwd)/aro-user.htpasswd user3 somepassword789

oc create secret generic htpass-secret --from-file=htpasswd=./aro-user.htpasswd -n openshift-config
oc apply -f htpasswd-cr.yaml
```

See other [supported identity providers](https://docs.openshift.com/container-platform/4.3/authentication/understanding-identity-provider.html#supported-identity-providers).

Login via CLI
-------------

```sh
oc login -u <kubeadmin-or-otheruser> --server=https://api.<aro-domain>:6443
Password: <enter-your-password>
```

Onboard to Azure Monitor
------------------------

Follow [these steps](https://docs.microsoft.com/en-us/azure/openshift/howto-azure-monitor-v4) to onbaord your ARO 4.3 cluster.

```sh
curl -LO  https://raw.githubusercontent.com/microsoft/OMS-docker/ci_feature/docs/openshiftV4/onboarding_azuremonitor_for_containers.sh
bash onboarding_azuremonitor_for_containers.sh <azureSubscriptionId> <azureRegionforLogAnalyticsWorkspace> <clusterName> <kubeconfigContextNameOftheCluster>
# e.g. bash onboarding_azuremonitor_for_containers.sh 27ac26cf-a9f0-4908-b300-9a4e9a0fb205 eastus myocp42 admin
```

Delete cluster
--------------

Disable monitoring (if enabled):

```
helm3 del azmon-containers-release-1
```

```sh
az aro delete -g "${ARO_RESOURCEGROUP}" -n "${ARO_CLUSTER}"

# (optional)
for subnet in "${ARO_CLUSTER}-master" "${ARO_CLUSTER}-worker"; do
  az network vnet subnet delete -g "${ARO_RESOURCEGROUP}" --vnet-name vnet -n "$subnet"
done
```
