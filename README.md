Azure Red Hat OpenShift 4 - Demo
================================

Demonstration of various Azure Red Hat Openshift features and basic steps to create and configure a cluster.
Always refer to the [official docs](https://docs.microsoft.com/en-us/azure/openshift/) for the latest up-to-date documentation as things may have changed since this was last updated.

Note:

* Red Hat's [Managed OpenShift Black Belt Team](https://cloud.redhat.com/experts/) also have great documentation on configuring ARO so check that out (it's more up-to-date than this repo!).

Index
-----

* [Prerequisites](#Prerequisites)
* [VNET setup](#create-the-cluster-virtual-network)
* [Create a default cluster](#create-a-default-cluster)
* [Create a private cluster](#create-a-private-cluster)
* [Configure Custom Domain and TLS](./TLS.md)
* [Configure bastion host access](#optional-configure-bastion-vnet-and-host-for-private-cluster-access)
* [Use an App Gateway](#optional-provision-an-application-gateway-v2-for-tls-and-waf)
* [Configure Identity Providers](#add-an-identity-provider-to-add-other-users)
* [Setup user roles](#setup-user-roles)
* [Setup in-cluster logging - Elasticsearch and Kibana](./logging)
* [Setup egress firewall - Azure Firewall](./firewall)
* [Onboard to Azure Monitor](#onboard-to-azure-monitor)
* [Deploy a demo app](./Demo.md)
* [Automation with Bicep (ARM DSL)](./automation)

Prerequisites
-------------

* Install the latest [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
* Log in to your Azure subscription from a console window:

```sh
az login
# Follow SSO prompts to authenticate
az account list -o table
az account set -s <subscription_id>
```

* Register the `Microsoft.RedHatOpenShift` resource provider to be able to create ARO clusters (only required once per Azure subscription):

```sh
az provider register -n Microsoft.RedHatOpenShift --wait
az provider show -n Microsoft.RedHatOpenShift -o table
```

* Install the [OpenShift CLI](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) for managing the cluster

```sh
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
tar -zxvf openshift-client-linux.tar.gz oc
sudo mv oc /usr/local/bin/
oc version
```

* (Optional) Install [Helm v3](https://helm.sh/docs/intro/install/) if you want to integrate with Azure Monitor
* (Optional) Install the `htpasswd` utility if you want to try HTPasswd as an OCP Identity Provider:

```sh
# Ubuntu
sudo apt install apache2-utils -y
```

Setup your shell environment file
---------------------------------

```sh
cp aro4-env.sh.template aro4-env.sh
# Edit aro4-env.sh to suit your environment
```

Create the cluster virtual network (Azure CLI)
----------------------------------------------

The VNET and subnet sizes here are for illustrative purposes only.
You need to design the network accordingly to your scale needs and existing networks (to avoid overlaps).

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
  --address-prefixes 10.0.2.0/24 \
  --service-endpoints Microsoft.ContainerRegistry

az network vnet subnet create \
  --resource-group $RESOURCEGROUP \
  --vnet-name $VNET \
  --name worker-subnet \
  --address-prefixes 10.0.3.0/24 \
  --service-endpoints Microsoft.ContainerRegistry

# Disable network policies for Private Link Service on your virtual network and subnets.
# This is a requirement for the ARO service to access and manage the cluster.
az network vnet subnet update \
  --name master-subnet \
  --resource-group $RESOURCEGROUP \
  --vnet-name $VNET \
  --disable-private-link-service-network-policies true
```

Create a default cluster (Azure CLI)
------------------------------------

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

Change Ingress Controller (public to private)
---------------------------------------------

If you have created a cluster with a public ingress (default) you can change that to private later or add a second ingress to handle private traffic whilst still serving public traffic.

* TODO

Create a private cluster (Azure CLI)
------------------------------------

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

If you used the `--domain` flag with an FQDN (e.g. `my.domain.com`) to create your cluster you'll need to configure DNS and a certificate authority for your API server and apps ingress.

If you used a shortname (e.g. "mycluster") with the `--domain` flag then you don't need to setup a custom domain and configure DNS/certs.
Then you can proceed to configure the [DNS and TLS/Certs settings](../TLS.md), if required - e.g. you set a FQDN custom domain.

In the later case, you'd get assigned an FQDN ending in `aroapp.io` like so:

```sh
https://console-openshift-console.apps.<shortname>.<region>.aroapp.io/
```

If needed, follow the steps in [TLS.md](./TLS.md).

(Optional) Configure bastion VNET and host (for private cluster access)
-----------------------------------------------------------------------

In order to connect to a private Azure Red Hat OpenShift cluster, you will need to perform CLI commands from a host that is either in the Virtual Network you created or in a Virtual Network that is peered with the Virtual Network the cluster was deployed to -- this could be from an on-prem host connected over an Express Route.

### Create the Bastion VNET and subnet

```sh
az network vnet create -g $RESOURCEGROUP -n utils-vnet --address-prefix 10.0.4.0/22 --subnet-name AzureBastionSubnet --subnet-prefix 10.0.4.0/27

az network public-ip create -g $RESOURCEGROUP -n bastion-ip --sku Standard
```

### Create the Bastion service

```sh
az network bastion create --name bastion-service --public-ip-address bastion-ip --resource-group $RESOURCEGROUP --vnet-name $UTILS_VNET --location $LOCATION
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
  --name $UTILS_VNET \
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
  --vnet-name $UTILS_VNET \
  --remote-vnet $vNet1Id \
  --allow-vnet-access
```

### Create the utility host subnet

```sh
az network vnet subnet create \
  --resource-group $RESOURCEGROUP \
  --vnet-name $UTILS_VNET \
  --name utils-hosts \
  --address-prefixes 10.0.5.0/24 \
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
  --image MicrosoftWindowsServer:WindowsServer:2022-Datacenter:latest \
  --vnet-name $UTILS_VNET \
  --subnet utils-hosts \
  --public-ip-address "" \
  --admin-username azureuser \
  --admin-password $winpass \
  --authentication-type password \
  --boot-diagnostics-storage $STORAGE_ACCOUNT \
  --generate-ssh-keys

az vm open-port --port 3389 --resource-group $RESOURCEGROUP --name jumpbox
```

**Recommended**: Enable update management or automatic guest OS patching.

### Connect to the utility host

Connect to the `jumpbox` host using the **Bastion** connection type and enter the username (`azureuser`) and password (use the value of `$winpass` set above or view the file `winpass.txt`).

Install the Microsoft Edge browser (if you used the Windows Server 2022 image for your VM then you can skip this step):

* Open a Powershell prompt

```powershell
$Url = "http://dl.delivery.mp.microsoft.com/filestreamingservice/files/c39f1d27-cd11-495a-b638-eac3775b469d/MicrosoftEdgeEnterpriseX64.msi"
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile "\MicrosoftEdgeEnterpriseX64.msi"
Start-Process msiexec.exe -Wait -ArgumentList '/I \MicrosoftEdgeEnterpriseX64.msi /norestart /qn'
```

Or you can [Download and deploy Microsoft Edge for business](https://www.microsoft.com/en-us/edge/business/download).

Install utilities:

* Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
* Install [Git For Windows](https://git-scm.com/) so you have access to a Bash shell
* Log in to your Azure subscription from a console window:

```sh
az login
# Follow SSO prompts (or create a Service Principal and login with that)
az account list -o table
az account set -s <subscription_id>
```

* Install the [OpenShift CLI](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) for managing the cluster ([example steps](https://www.openshift.com/blog/installing-oc-tools-windows))
* (Optional) Install [Helm v3](https://helm.sh/docs/intro/install/) if you want to integrate with Azure Monitor

Given this is a Windows jumpbox, you may need to install a Bash shell like Git Bash.

(Optional) Provision an Application Gateway v2 for TLS and WAF
--------------------------------------------------------------

This approach is not using the AppGw Ingress Controller but rather deploying an App Gateway WAFv2 in front of the ARO cluster and load-balancing traffic to the exposed ARO Routes for services.  This method can be used to selectively expose private routes for public access rahter than exposing the route directly.

```sh
az network vnet subnet create \
  --resource-group $RESOURCEGROUP \
  --vnet-name utils-vnet \
  --name myAGSubnet \
  --address-prefixes 10.0.6.0/24 \
  --service-endpoints Microsoft.ContainerRegistry

az network public-ip create \
  --resource-group $RESOURCEGROUP \
  --name myAGPublicIPAddress \
  --allocation-method Static \
  --sku Standard
```

If your ARO cluster is using Private ingress, you'll need to peer the AppGw  VNET and the ARO VNET (if you haven't already done so).

```sh
az network application-gateway create \
  --name myAppGateway \
  --location $LOCATION \
  --resource-group $RESOURCEGROUP \
  --capacity 1 \
  --sku WAF_v2 \
  --http-settings-cookie-based-affinity Disabled \
  --public-ip-address myAGPublicIPAddress \
  --vnet-name utils-vnet \
  --subnet myAGSubnet
```

Create or procure your App Gateway frontend PKCS #12 (*.PFX file) certificate chain (e.g. see below for manually, using Let's Encrypt):

```sh
# Specify the frontend domain for App Gw (must be different to the internal ARO domain, i.e. not *.apps.<domain>, but you can use *.<domain>)
APPGW_DOMAIN=$DOMAIN
./acme.sh --issue --dns -d "*.$APPGW_DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please --fullchain-file fullchain.cer --cert-file file.crt --key-file file.key
# Add the TXT entry for _acme-challenge to the $DOMAIN record set, then...
./acme.sh --renew --dns -d "*.$APPGW_DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please --fullchain-file fullchain.cer --cert-file file.crt --key-file file.key

cd ~/.acme.sh/\*.$APPGW_DOMAIN/
cat fullchain.cer \*.$APPGW_DOMAIN.key > gw-bundle.pem
openssl pkcs12 -export -out gw-bundle.pfx -in gw-bundle.pem
```

TODO: The following steps require Azure Portal access until I get around to writig the CLI/Powershell steps.

Define Azure DNS entries for the App Gateway frontend IP:

* Create a `*` A record with the public IP address of your App Gateway in your APPGW_DOMAIN domain (or better yet, create an alias record pointing to the public IP resource)

In the Listeners section, create a new HTTPS listener:

* Listener name: aro-route-https-listener
* Frontend IP: Public
* Port: 443
* Protocol: HTTPS
* Http Settings - choose to Upload a Certificate (upload the PFX file from earlier)
  * Cert Name: gw-bundle
  * PFX certificate file: gw-bundle.pfx
  * Password: ****** (what you used when creating the PFX file)
  * Additional settings - Multi site: (Enter your site host names, comma separated) - note: wildcard hostname not supported yet
    * e.g. rating-web.<domain>
  * Note: You can also create multiple listeners - one per site and re-use the certificate and select basic site

* Define Backend pools to point to the exposed ARO routes x n (one per web site/api)
* Define backend HTTP Settings (HTTPS, 443, Trusted CA) X 1

In the Backend pools section, create a new backend pool:

* Name: aro-routes
* Backend Targets: Enter the FQDN(s), e.g. `rating-web-workshop.apps.<domain>`
* Click Add

In the HTTP settings section, create a new HTTP setting:

* HTTP settings name: aro-route-https-settings
* Backend protocol: HTTPS
* Backend port: 443
* Use well known CA certificat: Yes (if you used one; otherwise upload your CA cer file)
* Override with new host name: Yes
* Choose: Pick host name from backend target

In the Rules section, define rules x n (one per website/api):

* Name: e.g. rating-web-rule
* Select the https listener above
* Enter backend target details - select the target and HTTP settings created above
* Click 'Add'

TODO: Define Health probes

Access the website/API via App Gateway: e.g. `https://rating-web.<domain>/`

Create a an ARO cluster and VNET with Bicep
--------------------------------------------

See: [automation](./automation/) section.

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
domain=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query clusterProfile.domain -o tsv | tr -d '[:space:]')
location=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query location -o tsv | tr -d '[:space:]')
apiServer=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query apiserverProfile.url -o tsv | tr -d '[:space:]')
webConsole=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query consoleProfile.url -o tsv | tr -d '[:space:]')

# If using default domain
oauthCallbackURL=https://oauth-openshift.apps.$domain.$location.aroapp.io/oauth2callback/AAD

# If using custom domain
oauthCallbackURL=https://oauth-openshift.apps.$DOMAIN/oauth2callback/AAD
```

Create an Azure Active Directory application:

```sh
clientSecret=$(openssl rand -base64 16)
echo $clientSecret > clientSecret.txt

appDisplayName="aro-auth-$(openssl rand -hex 4)"

appId=$(az ad app create \
  --query appId -o tsv \
  --display-name $appDisplayName \
  --reply-urls $oauthCallbackURL \
  --password $clientSecret)

tenantId=$(az account show --query tenantId -o tsv | tr -d '[:space:]')
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
# Azure Active Directory Graph.User.Read = 311a71cc-e848-46a1-bdf8-97ff7156d8e6
az ad app permission add \
 --api 00000002-0000-0000-c000-000000000000 \
 --api-permissions 311a71cc-e848-46a1-bdf8-97ff7156d8e6=Scope \
 --id $appId
```

Login to oc CLI as `kubeadmin`.

Create a secret to store AAD application secret:

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

See other [supported identity providers](https://docs.openshift.com/container-platform/4.4/authentication/understanding-identity-provider.html#supported-identity-providers).

Setup user roles
----------------

You can assign various roles or cluster roles to users.

```sh
oc adm policy add-cluster-role-to-user <role> <username>
```

You'll want to have at least one cluster-admin (similar to the `kubeadmin` user):

```sh
oc adm policy add-cluster-role-to-user cluster-admin <username>
```

If you get sign-in errors, you may need to delete users and/or identities:

```sh
oc get user
oc delete user <user>
oc get identity
oc delete identity <name>
```

Remove the kube-admin user
--------------------------

See: https://docs.openshift.com/aro/4/authentication/remove-kubeadmin.html

Ensure you have at least one other cluster-admin, sign in as that user then you can remove the `kube-admin` user:

```sh
oc delete secrets kubeadmin -n kube-system
```

Set up logging with Elasticsearch and Kibana or log forwarding to a Syslog server
---------------------------------------------------------------------------------

See [logging/](./logging/)

Setup egress firewall with Azure Firewall
-----------------------------------------

See [firewall/](./firewall/)

Onboard to Azure Monitor
------------------------

Refer to the [ARO Monitoring README](./monitoring) in this repo.

Deploy a demo app
-----------------

Follow the [Demo](./Demo.md) steps to deploy a sample microservices app.

Automation with Bicep (ARM DSL)
-------------------------------

See [Bicep](./automation/README.md) automation example.

(Optional) Delete cluster
-------------------------

Disable monitoring (if enabled):

```sh
helm del azmon-containers-release-1
```

or if using Arc-enabled monitoring, follow [these cleanup steps](https://github.com/clarenceb/aro4x-demo/tree/master/monitoring#option-2---arc-enabled-kubernetes-monioring-recommended).

```sh
az aro delete -g $RESOURCEGROUP -n $CLUSTER

# (optional)
az network vnet subnet delete -g $RESOURCEGROUP --vnet-name $VNET -n master-subnet
az network vnet subnet delete -g $RESOURCEGROUP --vnet-name $VNET -n worker-subnet
```

(optional) Delete Azure AD application (if using Azure AD for Auth)

Clean up clusters in a failed state
-----------------------------------

```sh
./cleanup-failed-clusters.sh
```

References
----------

* [Create an ARO 4 cluster](https://docs.microsoft.com/en-us/azure/openshift/tutorial-create-cluster) - Microsoft Docs
* [Supported identity providers in OCP 4.4](https://docs.openshift.com/container-platform/4.4/authentication/understanding-identity-provider.html#supported-identity-providers)
* [Overview of TLS termination and end to end TLS with Application Gateway](https://docs.microsoft.com/en-us/azure/application-gateway/ssl-overview)
