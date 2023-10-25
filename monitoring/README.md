Azure Monitor integration for ARO
=================================

Using Container Insights on ARO via Arc-enabled Kubernetes Monitoring
---------------------------------------------------------------------

First, Arc-enable the ARO cluster see [these steps](../arc/).

[Enable Azure Monitor Container Insights for Azure Arc enabled Kubernetes clusters](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-enable-arc-enabled-clusters)

Create a [Log Analytics Workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/azure-cli-log-analytics-workspace-sample#create-a-workspace-for-monitor-logs).

```sh
WORKSPACE_NAME="aro-logs"

az monitor log-analytics workspace create --resource-group $RESOURCEGROUP \
   --workspace-name $WORKSPACE_NAME --location $LOCATION

WORKSPACE_ID="$(az monitor log-analytics workspace show -n $WORKSPACE_NAME -g $RESOURCEGROUP --query id -o tsv)"

# Install the extension with **amalogs.useAADAuth=false**
# Non-cli onboarding is not supported for Arc-enabled Kubernetes clusters with ARO.
# Currently, only k8s-extension version 1.3.7 or below is supported.
# See: https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-enable-arc-enabled-clusters?tabs=create-cli%2Cverify-portal%2Cmigrate-cli#create-extension-instance
az extension remove --name k8s-extension
az extension add --name k8s-extension --version 1.3.7

az k8s-extension create \
    --name azuremonitor-containers \
    --cluster-name $ARC_CLUSTER_NAME \
    --resource-group $ARC_RESOURCE_GROUP \
    --cluster-type connectedClusters \
    --extension-type Microsoft.AzureMonitor.Containers \
    --configuration-settings logAnalyticsWorkspaceResourceID=$WORKSPACE_ID \
    --configuration-settings amalogs.useAADAuth=false
```

Check the "aro-arc" resource in the Azure Portal.  Click "Insights" to view the cluster health and metrics.

Adjust the [logging configuration](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-agent-config), if necessary.

To remove Arc enabled Monitoring (won't delete the Log Analytics workspace):

```sh
az k8s-extension delete \
    --name azuremonitor-containers \
    --cluster-type connectedClusters \
    --cluster-name $ARC_CLUSTER_NAME \
    --resource-group $ARC_RESOURCE_GROUP
```

To disconnect your cluster from Arc:

```sh
az connectedk8s delete --name $ARC_CLUSTER_NAME --resource-group $ARC_RESOURCE_GROUP

kubectl get crd -o name | grep azure | xargs kubectl delete
```
