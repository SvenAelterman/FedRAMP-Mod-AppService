param location string
param appInsightsName string
param logAnalyticsWorkspaceId string
param tags object

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'workspace'
  properties: {
    WorkspaceResourceId: logAnalyticsWorkspaceId
    Application_Type: 'web'
  }
  tags: tags
}

output instrumentationKey string = appInsights.properties.InstrumentationKey
output connectionString string = appInsights.properties.ConnectionString
