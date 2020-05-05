Azure Red Hat OpenShift 4.3
===========================

Prerequisites
-------------

* Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
* Install `az aro` extension:

```sh
az extension add -n aro --index https://az.aroapp.io/stable
```

* Register the `Microsoft.RedHatOpenShift` resource provider to be able to create ARO clusters:

```sh
az provider register -n Microsoft.RedHatOpenShift --wait
```

* Use/create an Azure Tenant where you have [Global Administrator](https://docs.microsoft.com/en-us/azure/openshift/howto-create-tenant) role
* Cluster an AAD application (client ID and secret) and service principal - [more info](https://docs.microsoft.com/en-us/azure/openshift/howto-aad-app-configuration)
* Install the [OpenShift CLI](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) for managing the cluster
* (Optional) Install [Helm v3](https://helm.sh/docs/intro/install/) if you want to integrate with Azure Monitor
* (Optional) Install the `htpasswd` utility if you want to try HTPasswd as an OCP Idenity Provider:

```sh
# Ubuntu
sudo apt install apache2-utils -y
```

Create Cluster
--------------

It normally takes about 35 minutes to create a cluster.

```sh
# Source variables into your shell environment
source ./aro43-env.sh

# Create resource group to hold cluster resources
az group create -g "${ARO_RESOURCEGROUP}" -l "${ARO_LOCATION}"

# Create the ARO virtual network
az network vnet create \
  -g "${ARO_RESOURCEGROUP}" \
  -n "${ARO_VNET}" \
  --address-prefixes 10.0.0.0/9 \
  >/dev/null

# Add two empty subnets to your virtual network (master subnet and worker subnet)
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

# Create the actual ARO cluster
az aro create \
  -g "${ARO_RESOURCEGROUP}" \
  -n "${ARO_CLUSTER}" \
  --vnet "${ARO_VNET}" \
  --master-subnet "${ARO_CLUSTER}-master" \
  --worker-subnet "${ARO_CLUSTER}-worker"
```

Login to Web console (initially as `kubeadmin`)
-----------------------------------------------

```sh
# Get Console URL from command output
az aro list -o table
# e.g. https://console-openshift-console.apps.<aro-domain>

# Get kubeadmin username and password
az aro list-credentials -g "${ARO_RESOURCEGROUP}" -n "${ARO_CLUSTER}"
```

Add an Identity Provider to add other users
-------------------------------------------

### HTPasswd

Configure [HTPasswd](https://docs.openshift.com/container-platform/4.3/authentication/identity_providers/configuring-htpasswd-identity-provider.html) identity provider.

```sh
htpasswd -c -B -b aro-user.htpasswd <user1> <somepassword1>
htpasswd -b $(pwd)/aro-user.htpasswd <user2> <somepassword2>
htpasswd -b $(pwd)/aro-user.htpasswd <user3> <somepassword3>

oc create secret generic htpass-secret --from-file=htpasswd=./aro-user.htpasswd -n openshift-config
oc apply -f htpasswd-cr.yaml
```

### Azure AD

See the [CLI steps](https://docs.microsoft.com/en-us/azure/openshift/configure-azure-ad-cli) to configure Azure AD or see below for the Portal steps.

```sh
domain=$(az aro show -g aro-v4-eastus -n aro4cbx --query clusterProfile.domain -o tsv)
location=$(az aro show -g aro-v4-eastus -n aro4cbx --query location -o tsv)
echo "OAuth callback URL: https://oauth-openshift.apps.$domain.$location.aroapp.io/oauth2callback/AAD"
# ==> https://oauth-openshift.apps.8tqc1kw4.eastus.aroapp.io/oauth2callback/AAD
```

Follow the instructions to [configure Azure AD as an idenity provider](https://docs.microsoft.com/en-us/azure/openshift/configure-azure-ad-ui) via the Azure Portal.

After creating the AAD application registration and setting the optional claims, add an OpenID Connection provider:

Issuer: `https://login.microsoftonline.com/<tenant-id>`

The provider name needs to match the Reply Url:

`https://oauth-openshift.apps.$domain.$location.aroapp.io/oauth2callback/<ProviderName>`

See other [supported identity providers](https://docs.openshift.com/container-platform/4.3/authentication/understanding-identity-provider.html#supported-identity-providers).

Login via `oc` CLI
------------------

```sh
oc login -u <kubeadmin-or-otheruser> --server=https://api.<aro-domain>:6443
Password: <enter-your-password>

oc status
```

(Optional) Onboard to Azure Monitor
------------------------------------

Follow [these steps](https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-azure-redhat4-setup) to onboard your ARO 4.3 cluster to Azure Monitor.

```sh
kubeconfigContext=$(kubectl config current-context)
azureAroV4ResourceId=$(az aro show -g "${ARO_RESOURCEGROUP}" -n "${ARO_CLUSTER}" --query "id" -o tsv)
curl -LO https://raw.githubusercontent.com/microsoft/OMS-docker/ci_feature/docs/aroV4/onboarding_azuremonitor_for_containers.sh
bash onboarding_azuremonitor_for_containers.sh $kubeconfigContext $azureAroV4ResourceId [<LogAnayticsWorkspaceResourceId>]
```

Deploy a demo app
-----------------

Follow the [Demo](./Demo.md) steps.

(Optional) Delete cluster
-------------------------

Disable monitoring (if enabled):

```
helm del azmon-containers-release-1
```

```sh
az aro delete -g "${ARO_RESOURCEGROUP}" -n "${ARO_CLUSTER}"

# (optional)
for subnet in "${ARO_CLUSTER}-master" "${ARO_CLUSTER}-worker"; do
  az network vnet subnet delete -g "${ARO_RESOURCEGROUP}" --vnet-name vnet -n "$subnet"
done
```

References
----------

* [Create an ARO 4 cluster](https://docs.microsoft.com/en-us/azure/openshift/tutorial-create-cluster) - Microsoft Docs
* [Supported identity providers in OCP 4.3](https://docs.openshift.com/container-platform/4.3/authentication/understanding-identity-provider.html#supported-identity-providers)