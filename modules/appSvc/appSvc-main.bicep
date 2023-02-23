param location string
param namingStructure string
param subnetId string
param frontendSubnetId string
param crName string
param appContainerImageName string
param apiContainerImageName string
param adminPanelContainerImageName string
param keyVaultName string
@description('The required FedRAMP logs will be sent to this workspace.')
param logAnalyticsWorkspaceId string

param deploymentNameStructure string

param apiAppSettings object
param webAppSettings object
param adminPanelAppSettings object

param crResourceGroupName string
param kvResourceGroupName string

@description('Specifies the Application Insights workspace to use. { instrumentationKey: "", connectionString: "" }')
param appInsights object = {}
param allowAccessSubnetIds array = []
param tags object = {}

// Create symbolic references to existing resources, to assign RBAC later
resource crRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: crResourceGroupName
  scope: subscription()
}

resource kvRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: kvResourceGroupName
  scope: subscription()
}

resource cr 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' existing = {
  name: crName
  scope: crRg
}

resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
  scope: kvRg
}

// Create an App Service Plan (the unit of compute and scale)
module appSvcPlanModule 'appSvcPlan.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'plan'), 64)
  params: {
    location: location
    appSvcPlanName: replace(namingStructure, '{rtype}', 'plan')
    tags: tags
  }
}

module frontendAppSvcPlanModule 'appSvcPlan.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'plan-frontend'), 64)
  params: {
    location: location
    appSvcPlanName: replace(namingStructure, '{rtype}', 'plan-frontend')
    tags: tags
  }
}

var webAppName = replace(namingStructure, '{rtype}', 'app-web')
var apiAppName = replace(namingStructure, '{rtype}', 'app-api')
var adminPanelAppName = replace(namingStructure, '{rtype}', 'app-admin')

module webAppSvcModule 'appSvc.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'app-web'), 64)
  params: {
    location: location
    tags: tags
    dockerImageAndTag: appContainerImageName
    subnetId: frontendSubnetId
    webAppName: webAppName
    crLoginServer: cr.properties.loginServer
    appSvcPlanId: frontendAppSvcPlanModule.outputs.id
    appSettings: webAppSettings
    appInsights: appInsights
    allowAccessSubnetIds: allowAccessSubnetIds
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

module adminPanelAppSvcModule 'appSvc.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'app-admin'), 64)
  params: {
    location: location
    tags: tags
    dockerImageAndTag: adminPanelContainerImageName
    subnetId: frontendSubnetId
    webAppName: adminPanelAppName
    crLoginServer: cr.properties.loginServer
    appSvcPlanId: frontendAppSvcPlanModule.outputs.id
    appSettings: adminPanelAppSettings
    appInsights: appInsights
    allowAccessSubnetIds: allowAccessSubnetIds
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

module apiAppSvcModule 'appSvc.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'app-api'), 64)
  params: {
    location: location
    tags: tags
    dockerImageAndTag: apiContainerImageName
    subnetId: subnetId
    webAppName: apiAppName
    crLoginServer: cr.properties.loginServer
    appSvcPlanId: appSvcPlanModule.outputs.id
    appSettings: apiAppSettings
    appInsights: appInsights
    allowAccessSubnetIds: allowAccessSubnetIds
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

module rolesModule '../../common-modules/roles.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'roles-appSvc'), 64)
  scope: subscription()
}

// Create RBAC assignments to allow the app services' managed identity to pull images from the Container Registry
module apiCrRoleAssignmentModule '../roleAssignments/roleAssignment-cr.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-cr-api'), 64)
  scope: crRg
  params: {
    crName: cr.name
    principalId: apiAppSvcModule.outputs.principalId
  }
}

module webCrRoleAssignmentModule '../roleAssignments/roleAssignment-cr.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-cr-web'), 64)
  scope: crRg
  params: {
    crName: cr.name
    principalId: webAppSvcModule.outputs.principalId
  }
}

module adminPanelCrRoleAssignmentModule '../roleAssignments/roleAssignment-cr.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-cr-adminpanel'), 64)
  scope: crRg
  params: {
    crName: cr.name
    principalId: adminPanelAppSvcModule.outputs.principalId
  }
}

// Create RBAC assignments to allow the app services' managed identity to read secrets from the Key Vault
module apiKvRoleAssignmentModule '../roleAssignments/roleAssignment-kv.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-kv-api'), 64)
  scope: kvRg
  params: {
    kvName: kv.name
    principalId: apiAppSvcModule.outputs.principalId
    roleDefinitionId: rolesModule.outputs.roles['Key Vault Secrets User']
  }
}

// LATER: Use an array of container images for creating App Services

output apiAppSvcPrincipalId string = apiAppSvcModule.outputs.principalId
output webAppSvcPrincipalId string = webAppSvcModule.outputs.principalId
output adminPanelAppSvcPrincipalId string = adminPanelAppSvcModule.outputs.principalId

output apiAppSvcName string = apiAppName
output webAppSvcName string = webAppName
output adminPanelAppsvcName string = adminPanelAppName
