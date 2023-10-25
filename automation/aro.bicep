param domain string
param masterSubnetId string
param workerSubnetId string
param clientId string
@secure()
param clientSecret string
@secure()
param pullSecret string
param clusterName string
param location string = resourceGroup().location

param podCidr string = '10.128.0.0/14'
param serviceCidr string = '172.30.0.0/16'
param apiServerVisibility string = 'Public'
param ingressVisibility string = 'Public'
param masterVmSku string = 'Standard_D8s_v3'
param prefix string = 'aro'
param fipsValidatedModules string = 'Disabled'
param encryptionAtHost string = 'Disabled'
param workerVmSize string = 'Standard_D4s_v3'
param workerDiskSizeGB int = 128
param workerCount int = 3

var ingressSpec = [
  {
    name: 'default'
    visibility: ingressVisibility
  }
]

var workerSpec = {
  name: 'worker'
  VmSize: workerVmSize
  diskSizeGB: workerDiskSizeGB
  count: workerCount
  encryptionAtHost: encryptionAtHost
}

var nodeRgName = '${prefix}-${take(uniqueString(resourceGroup().id, prefix), 5)}'

resource cluster 'Microsoft.RedHatOpenShift/OpenShiftClusters@2023-04-01' = {
  name: clusterName
  location: location
  properties: {
    clusterProfile: {
      domain: domain
      resourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', nodeRgName)
      pullSecret: pullSecret
      fipsValidatedModules: fipsValidatedModules
    }
    apiserverProfile: {
      visibility: apiServerVisibility
    }
    ingressProfiles: [for instance in ingressSpec: {
      name: instance.name
      visibility: instance.visibility
    }]
    masterProfile: {
      vmSize: masterVmSku
      subnetId: masterSubnetId
      encryptionAtHost: encryptionAtHost
    }
    workerProfiles: [
      {
        name: workerSpec.name
        vmSize: workerSpec.VmSize
        diskSizeGB: workerSpec.diskSizeGB
        subnetId: workerSubnetId
        count: workerSpec.count
        encryptionAtHost: workerSpec.encryptionAtHost
      }
    ]
    networkProfile: {
      podCidr:podCidr
      serviceCidr: serviceCidr
    }
    servicePrincipalProfile: {
      clientId: clientId
      clientSecret: clientSecret
    }
  }
}

output consoleUrl string = cluster.properties.consoleProfile.url
output apiUrl string = cluster.properties.apiserverProfile.url
