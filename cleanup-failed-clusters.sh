#!/bin/bash

aroRpObjectId="$(az ad sp list --filter "displayname eq 'Azure Red Hat OpenShift RP'" --query "[?appDisplayName=='Azure Red Hat OpenShift RP'].objectId" -o tsv)"

az role assignment list --assignee $aroRpObjectId

failedClusterResourceGroups="$(az aro list --query "[?provisioningState=='Failed'].{resourceGroup:clusterProfile.resourceGroupId}" -o tsv)"

for nodeResourceGroup in $failedClusterResourceGroups; do
  echo az role assignment create --assignee $aroRpObjectId --role "User Access Administrator" --scope $nodeResourceGroup
done

az aro list --query "[?provisioningState=='Failed'].{name:name, resourceGroup:resourceGroup}" -o tsv \
    | awk 'BEGIN { FS = "\t" } { print "az aro delete --yes -n " $1 " -g " $2 }' \
    | xargs -I {} bash -c '{}'
