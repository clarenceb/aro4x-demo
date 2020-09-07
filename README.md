Azure Red Hat OpenShift 4
=========================

Work in progress.

Topics
------

* Prerequisities
* Create the cluster virtual network
* Create a default cluster
* Create a private cluster (for private cluster access)
  * Configure bastion VNET and utility host
* Configure a custom domain and CA
* Add additional MachineSets (e.g. Infra nodes)
* Enable Azure Monitor integration
  * Enable Cluster Logging
* Provision an Application Gateway for WAF
* Demo App
  * Enable Router TLS

Prerequisites
-------------

* Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
* Log in to your Azure subscription from a console window:

```sh
az login
# Follow SSO prompts
az account list -o table
az account set -s <subscription_id>
```

* Register the `Microsoft.RedHatOpenShift` resource provider to be able to create ARO clusters:

```sh
az provider register -n Microsoft.RedHatOpenShift --wait
```

* Install the [OpenShift CLI](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) for managing the cluster
* (Optional) Install [Helm v3](https://helm.sh/docs/intro/install/) if you want to integrate with Azure Monitor
* (Optional) Install the `htpasswd` utility if you want to try HTPasswd as an OCP Identity Provider:

```sh
# Ubuntu
sudo apt install apache2-utils -y
```

Create the cluster virtual network
----------------------------------

```sh
# Source variables into your shell environment
source ./aro4-env.sh

# Create resource group to hold cluster resources
az group create -g $RESOURCEGROUP -l $LOCATION

# Create the ARO virtual network
az network vnet create \
  --resource-group $RESOURCEGROUP \
  --name $VNET \
  --address-prefixes 10.0.0.0/22

# Add two empty subnets to your virtual network (master subnet and worker subnet)
az network vnet subnet create \
  --resource-group $RESOURCEGROUP \
  --vnet-name $VNET \
  --name master-subnet \
  --address-prefixes 10.0.0.0/23 \
  --service-endpoints Microsoft.ContainerRegistry

az network vnet subnet create \
  --resource-group $RESOURCEGROUP \
  --vnet-name $VNET \
  --name worker-subnet \
  --address-prefixes 10.0.2.0/23 \
  --service-endpoints Microsoft.ContainerRegistry

# Disable network policies for Private Link Service on your virtual network and subnets.
# This is a requirement for the ARO service to access and manage the cluster.
az network vnet subnet update \
  --name master-subnet \
  --resource-group $RESOURCEGROUP \
  --vnet-name $VNET \
  --disable-private-link-service-network-policies true
```

Create a default cluster
------------------------

See the [official instructions](https://docs.microsoft.com/en-us/azure/openshift/tutorial-create-cluster).

It normally takes about 35 minutes to create a cluster.

```sh
# Create the ARO cluster
az aro create \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER \
  --vnet $VNET \
  --master-subnet master-subnet \
  --worker-subnet worker-subnet \
  --pull-secret @pull-secret.txt \
  --domain $DOMAIN

# pull-secret: OPTIONAL, but recommended
# domain: OPTIONAL custom domain for ARO (set in aro4-env.sh)
```

Create a private cluster
------------------------

See the [official instructions](https://docs.microsoft.com/en-us/azure/openshift/howto-create-private-cluster-4x).

It normally takes about 35 minutes to create a cluster.

```sh
# Create the ARO cluster
az aro create \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER \
  --vnet $VNET \
  --master-subnet master-subnet \
  --worker-subnet worker-subnet \
  --apiserver-visibility Private \
  --ingress-visibility Private \
  --pull-secret @pull-secret.txt \
  --domain $DOMAIN

# pull-secret: OPTIONAL, but recommended
# domain: OPTIONAL custom domain for ARO (set in aro4-env.sh)
```

(Optional) Configure custom domain and CA
-----------------------------------------

If you used the `--domain` flag to create your cluster you'll need to configure DNS and a certificate authority for your API server and apps ingress.

Follow the steps in [TLS.md](./TLS.md).

(Optional) Configure bastion VNET and host (for private cluster access)
-----------------------------------------------------------------------

In order to connect to a private Azure Red Hat OpenShift cluster, you will need to perform CLI commands from a host that is either in the Virtual Network you created or in a Virtual Network that is peered with the Virtual Network the cluster was deployed to -- this could be from an on-prem host connected over an Express Route.

### Create the Bastion VNET and subnet

```sh
az network vnet create -g $RESOURCEGROUP -n utils-vnet --address-prefix 10.1.0.0/16 --subnet-name AzureBastionSubnet --subnet-prefix 10.1.0.0/24

az network public-ip create -g $RESOURCEGROUP -n bastion-ip --sku Standard
```

### Create the Bastion service

```sh
az network bastion create --name bastion-service --public-ip-address bastion-ip --resource-group $RESOURCEGROUP --vnet-name utils-vnet --location $LOCATION
```

### Peer the bastion VNET and the ARO VNET

See how to peer VNETs from CLI: https://docs.microsoft.com/en-us/azure/virtual-network/tutorial-connect-virtual-networks-cli#peer-virtual-networks

```sh
# Get the id for myVirtualNetwork1.
vNet1Id=$(az network vnet show \
  --resource-group $RESOURCEGROUP \
  --name $VNET \
  --query id --out tsv)

# Get the id for myVirtualNetwork2.
vNet2Id=$(az network vnet show \
  --resource-group $RESOURCEGROUP \
  --name utils-vnet \
  --query id \
  --out tsv)

az network vnet peering create \
  --name aro-utils-peering \
  --resource-group $RESOURCEGROUP \
  --vnet-name $VNET \
  --remote-vnet $vNet2Id \
  --allow-vnet-access

az network vnet peering create \
  --name utils-aro-peering \
  --resource-group $RESOURCEGROUP \
  --vnet-name utils-vnet \
  --remote-vnet $vNet1Id \
  --allow-vnet-access
```

### Create the utility host subnet

```sh
az network vnet subnet create \
  --resource-group $RESOURCEGROUP \
  --vnet-name utils-vnet \
  --name utils-hosts \
  --address-prefixes 10.1.1.0/24 \
  --service-endpoints Microsoft.ContainerRegistry
```

### Create the utility host

```sh
STORAGE_ACCOUNT="jumpboxdiag$(openssl rand -hex 5)"
az storage account create -n $STORAGE_ACCOUNT -g $RESOURCEGROUP -l $LOCATION --sku Standard_LRS

winpass=$(openssl rand -base64 12)
echo $winpass > winpass.txt

az vm create \
  --resource-group $RESOURCEGROUP \
  --name jumpbox \
  --image MicrosoftWindowsServer:WindowsServer:2019-Datacenter:latest \
  --vnet-name utils-vnet \
  --subnet utils-hosts \
  --public-ip-address "" \
  --admin-username azureuser \
  --admin-password $winpass \
  --authentication-type password \
  --boot-diagnostics-storage $STORAGE_ACCOUNT \
  --generate-ssh-keys

az vm open-port --port 3389 --resource-group $RESOURCEGROUP --name jumpbox
```

### Connect to the utility host

Connect to the `jumpbox` host using the Bastion connection type and enter the username (`azureuser`) and password (value of `$winpass`) used above.

Install utilities:

* Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
* Log in to your Azure subscription from a console window:

```sh
az login
# Follow SSO prompts
az account list -o table
az account set -s <subscription_id>
```

* Install the [OpenShift CLI](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) for managing the cluster
* (Optional) Install [Helm v3](https://helm.sh/docs/intro/install/) if you want to integrate with Azure Monitor

Given this is a Windows jumpbox, you may need to install a Bash shell like Git Bash.

Provision an Application Gateway for TLS and WAF
------------------------------------------------

This approach is not using the AppGw Ingress Controller but rather deploying an AppGw in front of the ARO cluster and load-balancing traffic to the exposed ARO Routes for services.

```sh
az network vnet create \
  --name myAGVNet \
  --resource-group $RESOURCEGROUP \
  --location $LOCATION \
  --address-prefix 10.2.0.0/16 \
  --subnet-name myAGSubnet \
  --subnet-prefix 10.2.1.0/24

az network public-ip create \
  --resource-group $RESOURCEGROUP \
  --name myAGPublicIPAddress \
  --allocation-method Static \
  --sku Standard
```

If ARO cluster is using Private ingress, you'll need to peer the AppGw  VNET and the ARO VNET.

```sh
az network application-gateway create \
  --name myAppGateway \
  --location $LOCATION \
  --resource-group $RESOURCEGROUP \
  --capacity 1 \
  --sku WAF_v2 \
  --http-settings-cookie-based-affinity Disabled \
  --public-ip-address myAGPublicIPAddress \
  --vnet-name myAGVNet \
  --subnet myAGSubnet
```

TODO:

* Define custom DNS entries for the AppGw FE IP
* Define Backend pools to point to the exposed ARO routes x n (one per web site/api)
* Define backend HTTP Settings (HTTPS, 443, Trusted CA) X 1
* Define HTTPS listener and FE certifcate to the AppGw (PFX certificate file) x n (one per website/api) -- wildcard hostname not supported yet

```sh
./acme.sh --issue --dns -d "*.$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please --fullchain-file fullchain.cer --cert-file file.crt --key-file file.key
# Add the TXT entry for _acme-challenge to the $DOMAIN record set
./acme.sh --renew --dns -d "*.$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please --fullchain-file fullchain.cer --cert-file file.crt --key-file file.key

cd ~/.acme.sh/\*.aro.clarenceb.com/
cat fullchain.cer \*.aro.clarenceb.com.key > bundle.pem
openssl pkcs12 -export -out file.pfx -in bundle.pem
```

* Define rules x n (one per webiste/api)

Login to Web console
--------------------

```sh
# Get Console URL from command output
az aro list -o table
# ==> https://console-openshift-console.apps.<aro-domain>

# Get kubeadmin username and password
az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER
```

Login via `oc` CLI
------------------

```sh
API_URL=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query apiserverProfile.url -o tsv)
KUBEADMIN_PASSWD=$(az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER | jq -r .kubeadminPassword)

oc login -u kubeadmin -p $KUBEADMIN_PASSWD --server=$API_URL
oc status
```

Add an Identity Provider to add other users
-------------------------------------------

Add one or more identity providers to allow other users to login.  `kubeadmin` is intended as a temporary login to set up the cluster.

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

Configure OAuth callback URL:

```sh
domain=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query clusterProfile.domain -o tsv)
location=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query location -o tsv)
apiServer=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query apiserverProfile.url -o tsv)
webConsole=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query consoleProfile.url -o tsv)
oauthCallbackURL=https://oauth-openshift.apps.$domain.$location.aroapp.io/oauth2callback/AAD
```

Create an Azure Active Directory application:

```sh
clientSecret=$(openssl rand -base64 16)
echo $clientSecret > clientSecret.txt

appId=$(az ad app create \
  --query appId -o tsv \
  --display-name aro-auth \
  --reply-urls $oauthCallbackURL \
  --password $clientSecret)

tenantId=$(az account show --query tenantId -o tsv)
```

Create manifest file for optional claims to include in the ID Token:

```sh
cat > manifest.json<< EOF
[{
  "name": "upn",
  "source": null,
  "essential": false,
  "additionalProperties": []
},
{
"name": "email",
  "source": null,
  "essential": false,
  "additionalProperties": []
}]
EOF
```

Update AAD application's optionalClaims with a manifest:

```sh
az ad app update \
  --set optionalClaims.idToken=@manifest.json \
  --id $appId
```

Update AAD application scope permissions:

```sh
az ad app permission add \
 --api 00000002-0000-0000-c000-000000000000 \
 --api-permissions 311a71cc-e848-46a1-bdf8-97ff7156d8e6=Scope \ # Azure Active Directory Graph.User.Read
 --id $appId
```

Login to oc CLI as `kubeadmin`.

Create a secret o store AAD application secret:

```sh
oc create secret generic openid-client-secret-azuread \
  --namespace openshift-config \
  --from-literal=clientSecret=$clientSecret
```

Create OIDC configuration file for AAD:

```sh
cat > oidc.yaml<< EOF
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: AAD
    mappingMethod: claim
    type: OpenID
    openID:
      clientID: $appId
      clientSecret:
        name: openid-client-secret-azuread
      extraScopes:
      - email
      - profile
      extraAuthorizeParameters:
        include_granted_scopes: "true"
      claims:
        preferredUsername:
        - email
        - upn
        name:
        - name
        email:
        - email
      issuer: https://login.microsoftonline.com/$tenantId
EOF
```

Apply the configuration to the cluster:

```sh
oc apply -f oidc.yaml
```

Verify login to ARO console using AAD.

See other [supported identity providers](https://docs.openshift.com/container-platform/4.3/authentication/understanding-identity-provider.html#supported-identity-providers).

Setup user roles
----------------

You can assign various roles or cluster roles to users.
You'll want to have at least one cluster-admin (similar to the `kubeadmin` user):

```sh
oc adm policy add-cluster-role-to-user cluster-admin <username>
```

Onboard to Azure Monitor
------------------------

Follow [these steps](https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-azure-redhat4-setup) to onboard your ARO 4.3 cluster to Azure Monitor.

```sh
curl -o enable-monitoring.sh -L https://aka.ms/enable-monitoring-bash-script
# Edit the script to change the default workspace region:
# workspaceRegion="eastus"
# workspaceRegionCode="EUS"
# or specify the Log Ana;ytics Workpace ID: --workspace-id <workspace-resource-id>

adminUserName=$(az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER --query 'kubeadminUsername' -o tsv)
adminPassword=$(az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER --query 'kubeadminPassword' -o tsv)
apiServer=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query apiserverProfile.url -o tsv)

oc login $apiServer -u $adminUserName -p $adminPassword
# openshift project name for azure monitor for containers
openshiftProjectName="azure-monitor-for-containers"
# get the kube config context
kubeContext=$(oc config current-context)

# Integrate with the default workspace
azureAroV4ClusterResourceId=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query id -o tsv)

bash enable-monitoring.sh --resource-id $azureAroV4ClusterResourceId --kube-context $kubeContext # -workspace-id <workspace-resource-id>
```

Deploy a demo app
-----------------

Follow the [Demo](./Demo.md) steps.

### Setup router TLS

TODO

(Optional) Delete cluster
-------------------------

Disable monitoring (if enabled):

```sh
helm del azmon-containers-release-1
```

```sh
az aro delete -g $RESOURCEGROUP -n $CLUSTER

# (optional)
az network vnet subnet delete -g $RESOURCEGROUP --vnet-name $VNET -n master-subnet
az network vnet subnet delete -g $RESOURCEGROUP --vnet-name $VNET -n worker-subnet
```

References
----------

* [Create an ARO 4 cluster](https://docs.microsoft.com/en-us/azure/openshift/tutorial-create-cluster) - Microsoft Docs
* [Supported identity providers in OCP 4.4](https://docs.openshift.com/container-platform/4.4/authentication/understanding-identity-provider.html#supported-identity-providers)