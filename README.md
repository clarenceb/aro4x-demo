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

# Create the actual ARO cluster
az aro create \
  --resource-group $RESOURCEGROUP \
  --name $CLUSTER \
  --vnet $VNET \
  --master-subnet master-subnet \
  --worker-subnet worker-subnet
  # --pull-secret @pull-secret.txt # [OPTIONAL, but recommended]
  # --domain foo.example.com # [OPTIONAL] custom domain
```

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

(Optional) Onboard to Azure Monitor
------------------------------------

Follow [these steps](https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-azure-redhat4-setup) to onboard your ARO 4.3 cluster to Azure Monitor.

```sh
kubeconfigContext=$(kubectl config current-context)
azureAroV4ResourceId=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query "id" -o tsv)
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
az aro delete -g $RESOURCEGROUP -n $CLUSTER

# (optional)
az network vnet subnet delete -g $RESOURCEGROUP --vnet-name $VNET -n master-subnet
az network vnet subnet delete -g $RESOURCEGROUP --vnet-name $VNET -n worker-subnet
```

References
----------

* [Create an ARO 4 cluster](https://docs.microsoft.com/en-us/azure/openshift/tutorial-create-cluster) - Microsoft Docs
* [Supported identity providers in OCP 4.3](https://docs.openshift.com/container-platform/4.3/authentication/understanding-identity-provider.html#supported-identity-providers)