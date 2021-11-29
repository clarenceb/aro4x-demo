#!/bin/bash
#
# The script can be run to clean up ARO clusters that are in a failed state.

aroRpObjectId="$(az ad sp list --filter "displayname eq 'Azure Red Hat OpenShift RP'" --query "[?appDisplayName=='Azure Red Hat OpenShift RP'].objectId" -o tsv)"

echo "The Azure Red Hat OpenShift RP ($aroRpObjectId) currently the following remaining role assignments:"
az role assignment list --assignee $aroRpObjectId -o table

failedClusterResourceGroups="$(az aro list --query "[?provisioningState=='Failed'].{resourceGroup:clusterProfile.resourceGroupId}" -o tsv)"

for nodeResourceGroup in $failedClusterResourceGroups; do
  echo "Granting 'User Access Administrator' role to Azure Red Hat OpenShift RP ($aroRpObjectId) on scope $nodeResourceGroup"
  az role assignment create --assignee $aroRpObjectId --role "User Access Administrator" --scope $nodeResourceGroup
done

echo "Cleaning up failed ARO clusters..."
az aro list --query "[?provisioningState=='Failed'].{name:name, resourceGroup:resourceGroup}" -o tsv \
    | awk 'BEGIN { FS = "\t" } { print "az aro delete --yes -n " $1 " -g " $2 }' \
    | xargs -I {} bash -c '{}'

echo "The Azure Red Hat OpenShift RP ($aroRpObjectId) now has the following remaining role assignments:"
az role assignment list --assignee $aroRpObjectId -o table
