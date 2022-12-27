param webAppName string
param location string
param subnetId string
param dockerImageAndTag string
param crLoginServer string
param appSvcPlanId string
@description('The required FedRAMP logs will be sent to this workspace.')
param logAnalyticsWorkspaceId string
param tags object

param appSettings object = {}
@description('Specifies the Application Insights workspace to use. { instrumentationKey: "", connectionString: "" }')
param appInsights object = {}

param allowAccessSubnetIds array = []

var linuxFx = 'DOCKER|${crLoginServer}/${dockerImageAndTag}'
var appSvcKind = 'app,linux,container'

var hiddenRelatedTag = {
  'hidden-related:${appSvcPlanId}': 'empty'
}
// Merge the hidden tag with the parameter values
var actualTags = union(tags, hiddenRelatedTag)

// Create an application setting for the Container Registry URL
var dockerRegistryServerUrlSetting = {
  DOCKER_REGISTRY_SERVER_URL: 'https://${crLoginServer}'
}

var appInsightsInstrumentationKeySetting = (!empty(appInsights)) ? {
  APPINSIGHTS_INSTRUMENTATIONKEY: appInsights.instrumentationKey
  APPINSIGHTS_PROFILERFEATURE_VERSION: '1.0.0'
  APPINSIGHTS_SNAPSHOTFEATURE_VERSION: '1.0.0'
  APPLICATIONINSIGHTS_CONFIGURATION_CONTENT: ''
  APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.connectionString
  ApplicationInsightsAgent_EXTENSION_VERSION: '~3'
  DiagnosticServices_EXTENSION_VERSION: '~3'
  InstrumentationEngine_EXTENSION_VERSION: 'disabled'
  SnapshotDebugger_EXTENSION_VERSION: 'disabled'
  XDT_MicrosoftApplicationInsights_BaseExtensions: 'disabled'
  XDT_MicrosoftApplicationInsights_Mode: 'disabled'
  XDT_MicrosoftApplicationInsights_PreemptSdk: 'disabled'
} : {}

// Merge the setting with the parameter values
var actualAppSettings = union(appSettings, dockerRegistryServerUrlSetting, appInsightsInstrumentationKeySetting)

// Define the IP security restrictions for the App Service
var ipSecurityRestrictions = [for (subnetId, i) in allowAccessSubnetIds: {
  action: 'Allow'
  tag: 'Default'
  priority: 100 + i
  vnetSubnetResourceId: subnetId
}]

resource appSvc 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  identity: {
    // Create a system assigned managed identity to read Key Vault secrets and pull container images
    type: 'SystemAssigned'
  }
  kind: appSvcKind
  properties: {
    serverFarmId: appSvcPlanId
    virtualNetworkSubnetId: subnetId
    vnetImagePullEnabled: true
    vnetRouteAllEnabled: true // This is the default value
    httpsOnly: true
    keyVaultReferenceIdentity: 'SystemAssigned'

    siteConfig: {
      http20Enabled: true
      vnetRouteAllEnabled: true
      alwaysOn: true
      linuxFxVersion: linuxFx
      acrUseManagedIdentityCreds: true
      ftpsState: 'FtpsOnly'
      use32BitWorkerProcess: false

      logsDirectorySizeLimit: 35
      httpLoggingEnabled: true

      // Loop through all provided application settings
      appSettings: [for setting in items(actualAppSettings): {
        name: setting.key
        value: setting.value
      }]

      ipSecurityRestrictions: ipSecurityRestrictions

      #disable-next-line BCP037
      ipSecurityRestrictionsDefaultAction: empty(allowAccessSubnetIds) ? 'Allow' : 'Deny'

      // Do not use the same IP restrictions for the SCM site
      scmIpSecurityRestrictionsUseMain: false
    }
  }
  tags: actualTags
}

// Enable the Application Insights site extension
// Extensions are not supported in App Service for Containers
resource appServiceSiteExtension 'Microsoft.Web/sites/siteextensions@2022-03-01' = if (!empty(appInsights) && appSvcKind != 'app,linux,container') {
  parent: appSvc
  name: 'Microsoft.ApplicationInsights.AzureWebSites'
}

var appServiceLogCategories = [
  'AppServiceHttpLogs'
  'AppServiceConsoleLogs'
  'AppServiceAppLogs'
  'AppServiceAuditLogs'
  'AppServiceIPSecAuditLogs'
  'AppServicePlatformLogs'
]

resource diagnosticLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'Required FedRAMP logging - ${appSvc.name}'
  scope: appSvc
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [for category in appServiceLogCategories: {
      enabled: true
      category: category
      retentionPolicy: {
        days: 365
        enabled: true
      }
    }]
  }
}

// LATER: Configure health check endpoint

output appSvcName string = appSvc.name
output principalId string = appSvc.identity.principalId
output actualIpSecurityRestrictions array = ipSecurityRestrictions
