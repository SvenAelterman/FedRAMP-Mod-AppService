param webAppName string
param location string
param subnetId string
param dockerImageAndTag string
param crLoginServer string
param appSvcPlanId string

param tags object

param appSettings object = {}

var linuxFx = 'DOCKER|${crLoginServer}/${dockerImageAndTag}'

var hiddenRelatedTag = {
  'hidden-related:${appSvcPlanId}': 'empty'
}
// Merge the hidden tag with the parameter values
var actualTags = union(tags, hiddenRelatedTag)

// Create an application setting for the Container Registry URL
var dockerRegistryServerUrlSetting = {
  DOCKER_REGISTRY_SERVER_URL: 'https://${crLoginServer}'
}
// Merge the setting with the parameter values
var actualAppSettings = union(appSettings, dockerRegistryServerUrlSetting)

resource appSvc 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  identity: {
    // Create a system assigned managed identity to read Key Vault secrets and pull container images
    type: 'SystemAssigned'
  }
  kind: 'app,linux,container'
  properties: {
    serverFarmId: appSvcPlanId
    virtualNetworkSubnetId: subnetId
    httpsOnly: true
    keyVaultReferenceIdentity: 'SystemAssigned'

    siteConfig: {
      http20Enabled: true
      vnetRouteAllEnabled: true
      alwaysOn: true
      linuxFxVersion: linuxFx
      acrUseManagedIdentityCreds: true
      ftpsState: 'FtpsOnly'

      logsDirectorySizeLimit: 35
      httpLoggingEnabled: true

      // Loop through all provided application settings
      appSettings: [for setting in items(actualAppSettings): {
        name: setting.key
        value: setting.value
      }]

    }
  }
  tags: actualTags
}

output appSvcName string = appSvc.name
output principalId string = appSvc.identity.principalId
