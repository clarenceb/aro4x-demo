Azure Monitor integration for ARO
=================================

Using Container Insights on ARO via Arc-enabled Kubernetes Monitoring
---------------------------------------------------------------------

[Connect your ARO cluster to Azure Arc](https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/quickstart-connect-cluster)

Ensure your firewall (if using one) allows sufficient access:

- [Arc enabling the cluster](https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/quickstart-connect-cluster?tabs=azure-cli#meet-network-requirements)
- [Enabling Azure Monitor for Arc-enabled Kubernetes](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-enable-arc-enabled-clusters#prerequisites)

```sh
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.KubernetesConfiguration
az provider register --namespace Microsoft.ExtendedLocation

az provider show -n Microsoft.Kubernetes -o table
az provider show -n Microsoft.KubernetesConfiguration -o table
az provider show -n Microsoft.ExtendedLocation -o table

oc adm policy add-scc-to-user privileged system:serviceaccount:azure-arc:azure-arc-kube-aad-proxy-sa

ARC_RESOURCE_GROUP="aro-demo"
ARC_CLUSTER_NAME="aro-arc"
LOCATION="australiaeast"

az extension add --name connectedk8s
az extension add --name k8s-extension

az group create --name $ARC_RESOURCE_GROUP --location $LOCATION --output table
az connectedk8s connect --name $ARC_CLUSTER_NAME --resource-group $ARC_RESOURCE_GROUP --distribution openshift
az connectedk8s list --resource-group $ARC_RESOURCE_GROUP --output table

kubectl get deployments,pods -n azure-arc
```

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
