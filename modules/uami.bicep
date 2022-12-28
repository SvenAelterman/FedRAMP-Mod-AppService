param location string
param identityName string

param tags object = {}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: identityName
  location: location
  tags: tags
}

resource uamiLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: '${identityName}-lock'
  scope: uami
  properties: {
    level: 'CanNotDelete'
  }
}

// This is the ID that the PostgreSQL needs
output principalId string = uami.properties.principalId
output id string = uami.id
// This is the ID that the container registry needs
output applicationId string = uami.properties.clientId
output name string = uami.name
