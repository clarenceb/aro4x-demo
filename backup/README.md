Backup with Velero
==================

Install Velero CLI tool:

```sh
wget https://github.com/vmware-tanzu/velero/releases/download/v1.5.2/velero-v1.5.2-linux-amd64.tar.gz
tar xzf velero-v1.5.2-linux-amd64.tar.gz
sudo mv velero-v1.5.2-linux-amd64/velero /usr/local/bin

velero version
```

Create storage account and blob container for backups:

```sh
AZURE_BACKUP_RESOURCE_GROUP=Velero_Backups
LOCATION=australiaeast
az group create -n $AZURE_BACKUP_RESOURCE_GROUP --location $LOCATION

AZURE_STORAGE_ACCOUNT_ID="velero$(uuidgen | cut -d '-' -f5 | tr '[A-Z]' '[a-z]')"
az storage account create \
    --name $AZURE_STORAGE_ACCOUNT_ID \
    --resource-group $AZURE_BACKUP_RESOURCE_GROUP \
    --sku Standard_GRS \
    --encryption-services blob \
    --https-only true \
    --kind BlobStorage \
    --access-tier Hot

BLOB_CONTAINER=velero
az storage container create -n $BLOB_CONTAINER --public-access off --account-name $AZURE_STORAGE_ACCOUNT_ID
```

Create Azure Service Principal and Velero configuration file:

```sh
CLUSTER=cluster
ARO_RG=aro-v4

export AZURE_RESOURCE_GROUP=$(az aro show --name $CLUSTER --resource-group $ARO_RG | jq -r .clusterProfile.resourceGroupId | cut -d '/' -f 5,5)

AZURE_SUBSCRIPTION_ID=$(az account list --query '[?isDefault].id' -o tsv)
AZURE_TENANT_ID=$(az account list --query '[?isDefault].tenantId' -o tsv)

az ad sp create-for-rbac --name "http://velero-aro4" --role "Contributor" --scopes  /subscriptions/$AZURE_SUBSCRIPTION_ID > velero-sp.json

AZURE_CLIENT_SECRET=$(jq .password <velero-sp.json)
AZURE_CLIENT_ID=$(az ad sp list --display-name "velero-aro4" --query '[0].appId' -o tsv)

cat << EOF  > ./credentials-velero.yaml
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
AZURE_RESOURCE_GROUP=${AZURE_RESOURCE_GROUP}
AZURE_CLOUD_NAME=AzurePublicCloud
EOF
```

Install Velero in ARO:

```sh
velero install \
    --provider azure \
    --plugins velero/velero-plugin-for-microsoft-azure:v1.1.0 \
    --bucket $BLOB_CONTAINER \
    --secret-file ./credentials-velero.yaml \
    --backup-location-config resourceGroup=$AZURE_BACKUP_RESOURCE_GROUP,storageAccount=$AZURE_STORAGE_ACCOUNT_ID \
    --snapshot-location-config apiTimeout=15m \
    --velero-pod-cpu-limit="0" --velero-pod-mem-limit="0" \
    --velero-pod-mem-request="0" --velero-pod-cpu-request="0"
```

Backup a namespace:


```sh
velero create backup mydemo1-1 --include-namespaces=mydemo1

velero backup describe mydemo1-1
velero backup logs mydemo1-1

oc get backups -n velero mydemo1-1 -o yaml
```

Backup a namesapce with disk snapshots (PVs):

```sh
velero backup create mydemo1-2 --include-namespaces=mydemo1 --snapshot-volumes=true --include-cluster-resources=true

velero backup describe mydemo1-2
velero backup logs mydemo1-2

oc get backups -n velero mydemo1-2 -o yaml
```

Restore a backup:

```sh
oc get backups -n velero
velero restore create restore-mydemo1-1 --from-backup mydemo1-1

velero restore describe restore-mydemo1-1
velero restore logs restore-mydemo1-1

oc get restore -n velero restore-mydemo1-1 -o yaml
```

Restore a backup with disk snapshots (PVs):

```sh
oc get backups -n velero
velero restore create restore-mydemo1-2 --from-backup mydemo1-2 --exclude-resources="nodes,events,events.events.k8s.io,backups.ark.heptio.com,backups.velero.io,restores.ark.heptio.com,restores.velero.io"

velero restore describe restore-mydemo1-2
velero restore logs restore-mydemo1-2

oc get restore -n velero restore-mydemo1-2 -o yaml
```

Uninstall Velero:

```sh
kubectl delete namespace/velero clusterrolebinding/velero
kubectl delete crds -l component=velero
```

Delete storage account:

```sh
az storage account delete --name $AZURE_STORAGE_ACCOUNT_ID --resource-group $AZURE_BACKUP_RESOURCE_GROUP
```

Delete service principal:

```sh
az ad sp create-for-rbac --id $AZURE_CLIENT_ID
```
