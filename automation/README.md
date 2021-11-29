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
pullSecret=$(cat pull-secret.txt)

clientObjectId="$(az ad sp list --filter "AppId eq '$clientId'" --query "[?appId=='$clientId'].objectId" -o tsv)"
aroRpObjectId="$(az ad sp list --filter "displayname eq 'Azure Red Hat OpenShift RP'" --query "[?appDisplayName=='Azure Red Hat OpenShift RP'].objectId" -o tsv)"

az group create -n $RESOURCEGROUP -l $LOCATION

az deployment group create \
    -f ./automation/main.bicep \
    -g $RESOURCEGROUP \
    --parameters clientId=$clientId \
        clientObjectId=$clientObjectId \
        clientSecret=$clientSecret \
        aroRpObjectId=$aroRpObjectId \
        domain=$domain \
        pullSecret=$pullSecret
```

Then you can proceed to configure the [DNS and TLS settings](../TLS.md).

Resources
---------

* https://github.com/Azure/bicep
* https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep
