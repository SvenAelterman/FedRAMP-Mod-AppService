param location string
param identityName string

param tags object = {}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: identityName
  location: location
  tags: tags
}

// This is the ID that the PostgreSQL needs
output principalId string = uami.properties.principalId
output id string = uami.id
// This is the ID that the container registry needs
output applicationId string = uami.properties.clientId
