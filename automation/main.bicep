targetScope = 'subscription'

param domain string
param clientId string
param clientSecret string
param pullSecret string

resource aroRg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: 'aro-demos'
  location: deployment().location
}

module vnet 'vnet.bicep' = {
  name: 'aro-vnet'
  scope: aroRg
}

var vnetRoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' // contributor

resource vnetContribRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(vnetRoleDefinitionId, aroRg.id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vnetRoleDefinitionId)
    principalId: clientId
    principalType: 'ServicePrincipal'
  }
}

module aro 'aro.bicep' = {
  name: 'aro-cluster'
  scope: aroRg
  params: {
    domain: domain
    masterSubnetId: vnet.outputs.masterSubnetId
    workerSubnetId: vnet.outputs.workerSubnetId
    clientId: clientId
    clientSecret: clientSecret
    pullSecret: pullSecret
  }
}
