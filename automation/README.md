Bicep example to create ARO cluster
===================================

Start of a Bicep example.
Creates a basic ARO cluster in a new resource group and VNET.

You will need owner level access on the Subscription.

```sh
az ad sp create-for-rbac -n http://aro-demo-sp --skip-assignment > aro-sp.json
clientId="$(jq -r .appId <aro-sp.json)"
clientSecret="$(jq -r .password <aro-sp.json)"
pullSecret=$(cat pull-secret.txt)
domain="example.com"

az deployment sub create \
    -f ./main.bicep \
    -l australiaeast \
    --parameters domain=$domain pullSecret=$pullSecret clientId=$clientId clientSecret=$clientSecret
```

Resources
---------

* https://github.com/Azure/bicep
* https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep
