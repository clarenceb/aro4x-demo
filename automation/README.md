Bicep example to create ARO cluster
===================================

Start of a Bicep example.
Creates a basic ARO cluster in a new resource group and VNET.

You will need owner level access on the Subscription to execute the deployment.
You'll also need permission to create an Azure AD Service Principal.

```sh
source ../aro4-env.sh

sp_display_name="aro-demo-sp"
az ad sp create-for-rbac -n http://$sp_display_name > aro-sp.json

clientId="$(jq -r .appId <aro-sp.json)"
clientSecret="$(jq -r .password <aro-sp.json)"
pullSecret=$(cat ../pull-secret.txt)
tenantId=$(az account show --query tenantId -o tsv)

clientObjectId="$(az ad sp list --filter "AppId eq '$clientId'" --query "[?appId=='$clientId'].id" -o tsv)"
 
aroRpObjectId="$(az ad sp list --filter "displayname eq 'Azure Red Hat OpenShift RP'" --query "[?appDisplayName=='Azure Red Hat OpenShift RP']" --query "[?appOwnerOrganizationId=='$tenantId'].id" -o tsv | head -1)"

az group create -n $RESOURCEGROUP -l $LOCATION

az deployment group create \
    -f ./main.bicep \
    -g $RESOURCEGROUP \
    --parameters clientId=$clientId \
        clientObjectId=$clientObjectId \
        clientSecret=$clientSecret \
        aroRpObjectId=$aroRpObjectId \
        domain=$DOMAIN \
        pullSecret=$pullSecret
```

Then you can proceed to configure the [DNS and TLS/Certs settings](../TLS.md), if required - e.g. you set a FQDN custom domain.
If you set only a name e.g. "mycluster" and not a FQDN "mycluster.com.au" then you don't need to set custom DNS and configure custom certs.
The assigned FQDN whe you only specify the short name will be in the format:

```sh
https://console-openshift-console.apps.<shortname>.<region>.aroapp.io/
```

Resources
---------

* https://github.com/Azure/bicep
* https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep
