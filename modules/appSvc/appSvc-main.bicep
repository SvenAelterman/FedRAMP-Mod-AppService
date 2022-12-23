param location string
param namingStructure string
param subnetId string
param crName string
param appContainerImageName string
param apiContainerImageName string
param dbFqdn string
param databaseName string
param keyVaultName string

param deploymentNameStructure string

param dbUserNameSecretName string
param dbPasswordSecretName string
param emailTokenSecretName string

param crResourceGroupName string
param kvResourceGroupName string

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

// Generate App Service setting values for Key Vault secret references
module keyVaultRefs '../../common-modules/appSvcKeyVaultRefs.bicep' = {
  name: 'appSvcKeyVaultRefs'
  scope: kvRg
  params: {
    keyVaultName: keyVaultName
    secretNames: [
      dbUserNameSecretName
      dbPasswordSecretName
      emailTokenSecretName
    ]
  }
}

var dbUserNameConfigValue = keyVaultRefs.outputs.keyVaultRefs[0]
var dbPasswordConfigValue = keyVaultRefs.outputs.keyVaultRefs[1]
var emailTokenConfigValue = keyVaultRefs.outputs.keyVaultRefs[2]

// Create an App Service Plan (the unit of compute and scale)
module appSvcPlanModule 'appSvcPlan.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'plan'), 64)
  params: {
    location: location
    namingStructure: namingStructure
  }
}

var webAppName = replace(namingStructure, '{rtype}', 'app-web')
var apiAppName = replace(namingStructure, '{rtype}', 'app-api')

module webAppSvcModule 'appSvc.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'app-web'), 64)
  params: {
    location: location
    tags: tags
    dockerImageAndTag: appContainerImageName
    databaseName: databaseName
    dbFqdn: dbFqdn
    subnetId: subnetId
    webAppName: webAppName
    // LATER: Probably won't need all these
    dbPasswordConfigValue: dbPasswordConfigValue
    dbUserNameConfigValue: dbUserNameConfigValue
    crLoginServer: cr.properties.loginServer
    appSvcPlanId: appSvcPlanModule.outputs.id
    emailTokenConfigValue: emailTokenConfigValue
  }
}

module apiAppSvcModule 'appSvc.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'app-api'), 64)
  params: {
    location: location
    tags: tags
    dockerImageAndTag: apiContainerImageName
    databaseName: databaseName
    dbFqdn: dbFqdn
    subnetId: subnetId
    webAppName: apiAppName
    dbPasswordConfigValue: dbPasswordConfigValue
    dbUserNameConfigValue: dbUserNameConfigValue
    crLoginServer: cr.properties.loginServer
    appSvcPlanId: appSvcPlanModule.outputs.id
    emailTokenConfigValue: emailTokenConfigValue
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

output apiAppSvcPrincipalId string = apiAppSvcModule.outputs.principalId
output webAppSvcPrincipalId string = webAppSvcModule.outputs.principalId
