Azure Monitor integration for ARO
=================================

Using Container Insights on ARO via Arc-enabled Kubernetes Monitoring
---------------------------------------------------------------------

First, Arc-enable the ARO cluster see [these steps](../arc/).

[Enable Azure Monitor Container Insights for Azure Arc enabled Kubernetes clusters](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-enable-arc-enabled-clusters)

Create a [Log Analytics Workspace](https://docs.microsoft.com/en-us/azure/azure-monitor/logs/quick-create-workspace-cli).

```sh
WORKSPACE_NAME="aro-logs"

WORKSPACE_ID="$(az monitor log-analytics workspace show -n $WORKSPACE_NAME -g $ARC_RESOURCE_GROUP --query id -o tsv)"

az k8s-extension create \
    --name azuremonitor-containers \
    --cluster-name $ARC_CLUSTER_NAME \
    --resource-group $ARC_RESOURCE_GROUP \
    --cluster-type connectedClusters \
    --extension-type Microsoft.AzureMonitor.Containers \
    --configuration-settings logAnalyticsWorkspaceResourceID=$WORKSPACE_ID
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
