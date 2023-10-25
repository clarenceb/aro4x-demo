Arc-enable your ARO cluster
===========================

[Connect your ARO cluster to Azure Arc](https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/quickstart-connect-cluster)

Ensure your firewall (if using one) allows sufficient access:

- [Arc enabling the cluster](https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/quickstart-connect-cluster?tabs=azure-cli#meet-network-requirements)
- [Enabling Azure Monitor for Arc-enabled Kubernetes](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-enable-arc-enabled-clusters#prerequisites)

Register required providers:

```sh
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.KubernetesConfiguration
az provider register --namespace Microsoft.ExtendedLocation

az provider show -n Microsoft.Kubernetes -o table
az provider show -n Microsoft.KubernetesConfiguration -o table
az provider show -n Microsoft.ExtendedLocation -o table
```

Login to your ARO cluster with `oc` CLI:

```sh
API_URL=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query apiserverProfile.url -o tsv)
KUBEADMIN_PASSWD=$(az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER | jq -r .kubeadminPassword)

oc login -u kubeadmin -p $KUBEADMIN_PASSWD --server=$API_URL
oc status
```

Set required SCC policy for Arc to work in ARO:

```sh
oc adm policy add-scc-to-user privileged system:serviceaccount:azure-arc:azure-arc-kube-aad-proxy-sa
```

Onboard the ARO cluster to Arc:

```sh
ARC_RESOURCE_GROUP="aro-test"
ARC_CLUSTER_NAME="aro-arc"
ARC_LOCATION="australiaeast"

az extension add --name connectedk8s
az extension add --name k8s-extension

az group create --name $ARC_RESOURCE_GROUP --location $ARC_LOCATION --output table
az connectedk8s connect --name $ARC_CLUSTER_NAME --resource-group $ARC_RESOURCE_GROUP --distribution openshift
az connectedk8s list --resource-group $ARC_RESOURCE_GROUP --output table

kubectl get deployments,pods -n azure-arc
```

Resources
---------

- [Quickstart: Connect an existing Kubernetes cluster to Azure Arc](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/quickstart-connect-cluster?tabs=azure-cli)
