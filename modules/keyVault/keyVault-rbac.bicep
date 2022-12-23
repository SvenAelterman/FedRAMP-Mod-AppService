param principalId string
param keyVaultName string
param roleName string

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

module rolesModule '../../common-modules/roles.bicep' = {
  name: 'kv-roles-${uniqueString(principalId, roleName, keyVaultName)}'
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, keyVault.id, roleName)
  scope: keyVault
  properties: {
    principalId: principalId
    roleDefinitionId: rolesModule.outputs.roles[roleName]
  }
}
