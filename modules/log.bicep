param namingStructure string
param location string

param tags object = {}

resource logAnalyticsWS 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: replace(namingStructure, '{rtype}', 'log')
  location: location
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

output workspaceName string = logAnalyticsWS.name
output workspaceId string = logAnalyticsWS.id
