param namingStructure string
param location string
param savedQueryStorageAccountName string

param tags object = {}

resource logAnalyticsWS 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: replace(namingStructure, '{rtype}', 'log')
  location: location
  properties: {
    forceCmkForQuery: true
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
  tags: tags
}

// Enable a delete lock on this critical resource
resource lock 'Microsoft.Authorization/locks@2017-04-01' = {
  name: '${logAnalyticsWS.name}-lck'
  scope: logAnalyticsWS
  properties: {
    level: 'CanNotDelete'
  }
}

resource savedQueryStorageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' existing = {
  name: savedQueryStorageAccountName
}

// Set the storage account for saved queries
resource logLinkedStorageAccount 'Microsoft.OperationalInsights/workspaces/linkedStorageAccounts@2020-08-01' = {
  name: 'Query'
  parent: logAnalyticsWS
  properties: {
    storageAccountIds: [
      savedQueryStorageAccount.id
    ]
  }
}

output workspaceName string = logAnalyticsWS.name
output workspaceId string = logAnalyticsWS.id
