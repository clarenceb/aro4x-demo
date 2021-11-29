param vnetId string
param clientObjectId string
param aroRpObjectId string

var roleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' // contributor

resource clusterRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(vnetId, roleDefinitionId, clientObjectId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: clientObjectId
    principalType: 'ServicePrincipal'
  }
}

resource aroRpRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(vnetId, roleDefinitionId, aroRpObjectId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: aroRpObjectId
    principalType: 'ServicePrincipal'
  }
}
