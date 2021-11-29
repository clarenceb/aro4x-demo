param clientId string
param clientObjectId string
param clientSecret string
param aroRpObjectId string
param domain string
param pullSecret string
param clusterName string = 'cluster'

module vnet 'vnet.bicep' = {
  name: 'aro-vnet'
}

module vnetRoleAssignments 'roleAssignments.bicep' = {
  name: 'role-assignments'
  params: {
    vnetId: vnet.outputs.vnetId
    clientObjectId: clientObjectId
    aroRpObjectId: aroRpObjectId
  }
}

module aro 'aro.bicep' = {
  name: 'aro'
  params: {
    domain: domain
    masterSubnetId: vnet.outputs.masterSubnetId
    workerSubnetId: vnet.outputs.workerSubnetId
    clientId: clientId
    clientSecret: clientSecret
    pullSecret: pullSecret
    clusterName: clusterName
  }

  dependsOn: [
    vnetRoleAssignments
  ]
}
