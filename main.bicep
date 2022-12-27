targetScope = 'subscription'

@allowed([
  'eastus2'
  'eastus'
])
param location string
@allowed([
  'TEST'
  'DEMO'
  'PROD'
])
param environment string
param workloadName string

@allowed([
  '14'
])
param postgresqlVersion string
@secure()
param dbAdminPassword string
@secure()
param dbAppSvcPassword string
@secure()
param dbAppSvcLogin string
param databaseName string

@secure()
param emailToken string

param apiAppSettings object
param webAppSettings object

param appContainerImageName string
param apiContainerImageName string

param apiHostName string
param webHostName string

@minValue(0)
@maxValue(128)
param vNetAddressSpaceOctet4Min int
param vNetAddressSpace string
@minValue(24)
@maxValue(25)
param vNetCidr int
@maxValue(28)
@minValue(27)
param subnetCidr int

// Optional parameters
param dbAadGroupObjectId string = ''
param dbAadGroupName string = ''
param deployBastion bool = false
param deployDefaultSubnet bool = false
param deployComputeRg bool = false
param tags object = {}
param sequence int = 1
param namingConvention string = '{wloadname}-{env}-{rtype}-{loc}-{seq}'
param deploymentTime string = utcNow()
param keyNameRandomInit string = utcNow()

// To allow for shared DNS Zone
param coreSubscriptionId string
param coreDnsZoneResourceGroupName string

var sequenceFormatted = format('{0:00}', sequence)

var deploymentNameStructure = '${workloadName}-${environment}-{rtype}-${deploymentTime}'
// Naming structure only needs the resource type ({rtype}) replaced
var thisNamingStructure = replace(replace(replace(namingConvention, '{env}', environment), '{loc}', location), '{seq}', sequenceFormatted)
var namingStructure = replace(thisNamingStructure, '{wloadname}', workloadName)

// Create resource groups
resource networkingRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(namingStructure, '{rtype}', 'rg-networking')
  location: location
  tags: tags
}

resource containerRegRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(namingStructure, '{rtype}', 'rg-containerregistry')
  location: location
  tags: tags
}

resource appsRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(namingStructure, '{rtype}', 'rg-apps')
  location: location
  tags: tags
}

resource dataRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(namingStructure, '{rtype}', 'rg-data')
  location: location
  tags: tags
}

resource securityRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(namingStructure, '{rtype}', 'rg-security')
  location: location
  tags: tags
}

resource computeRg 'Microsoft.Resources/resourceGroups@2021-04-01' = if (deployComputeRg) {
  name: replace(namingStructure, '{rtype}', 'rg-compute')
  location: location
  tags: tags
}

// resource storageRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
//   name: replace(rgNamingStructure, '{wloadname}', '${workloadName}-storage')
//   location: location
//   tags: tags
// }

resource coreDnsZoneRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: coreDnsZoneResourceGroupName
  scope: subscription(coreSubscriptionId)
}

var SubnetSize = 32 - subnetCidr
var subnetBoundaryArray = [for i in range(0, SubnetSize): 2]
var subnetBoundary = reduce(subnetBoundaryArray, 1, (cur, next) => cur * next)

// Create virtual network and subnets
var subnets = {
  privateEndpoints: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (0 * subnetBoundary)))}/${subnetCidr}'
    serviceEndpoints: []
    delegation: ''
    securityRules: []
  }
  postgresql: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (1 * subnetBoundary)))}/${subnetCidr}'
    serviceEndpoints: []
    delegation: 'Microsoft.DBforPostgreSQL/flexibleServers'
    securityRules: loadJsonContent('content/nsgrules/postgresql.json')
  }
  apps: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (2 * subnetBoundary)))}/${subnetCidr}'
    serviceEndpoints: []
    delegation: 'Microsoft.Web/serverFarms'
    securityRules: []
  }
  appgw: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (3 * subnetBoundary)))}/${subnetCidr}'
    // Allow the Application Gateway to access the App Services
    serviceEndpoints: [
      {
        service: 'Microsoft.Web'
        locations: [
          '*'
        ]
      }
    ]
    delegation: ''
    securityRules: loadJsonContent('content/nsgrules/appGw.json')
  }
}

var defaultSubnet = deployDefaultSubnet ? {
  default: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (4 * subnetBoundary)))}/${subnetCidr}'
    // Allow compute resources in the default subnet to bypass App Svc IP restrictions
    serviceEndpoints: [
      {
        service: 'Microsoft.Web'
        locations: [
          '*'
        ]
      }
    ]
    delegation: ''
    securityRules: loadJsonContent('content/nsgrules/default.json')
  }
} : {}

var azureBastionSubnet = deployBastion ? {
  AzureBastionSubnet: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (5 * subnetBoundary)))}/${subnetCidr}'
    serviceEndpoints: []
    delegation: ''
    securityRules: loadJsonContent('content/nsgrules/bastion.json')
  }
} : {}

var subnetsToDeploy = union(subnets, azureBastionSubnet, defaultSubnet)

// Create the basic network resources: Virtual Network + subnets, Network Security Groups
module networkModule 'modules/network.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'network'), 64)
  scope: networkingRg
  params: {
    location: location
    deploymentNameStructure: deploymentNameStructure
    subnetDefs: subnetsToDeploy
    vNetAddressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min))}/${vNetCidr}'
    namingStructure: namingStructure
    tags: tags
  }
}

// Create a valid name for the PostgreSQL flexible server
module postgresqlShortNameModule 'common-modules/shortname.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'pg-name'), 64)
  scope: dataRg
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'pg'
    sequence: sequence
    workloadName: workloadName
  }
}

var corePrivateDnsZoneNames = [
  // Do not change order, values are referenced by index later
  // The environment suffix for container registry includes a . but storage doesn't
  'privatelink${az.environment().suffixes.acrLoginServer}'
  'privatelink.vaultcore.azure.net'
  'privatelink.blob.${az.environment().suffixes.storage}'
]

// Create DNS zones in the workload subscription specific to this workload (PostgreSQL)
module pgDnsZonesModule 'modules/privateDnsZone.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-pg'), 64)
  scope: networkingRg
  params: {
    zoneName: '${postgresqlShortNameModule.outputs.shortName}.private.postgres.database.azure.com'
    tags: tags
  }
}

// Link the private DNS Zones to the virtual network
module pgDnsZonesLinkModule 'modules/privateDnsZoneVNetLink.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-link-pg'), 64)
  scope: networkingRg
  params: {
    dnsZoneName: '${postgresqlShortNameModule.outputs.shortName}.private.postgres.database.azure.com'
    vNetId: networkModule.outputs.vNetId
  }
}

// Create DNS zones in the shared core
module corePrivateDnsZonesModule 'modules/privateDnsZone.bicep' = [for zoneName in corePrivateDnsZoneNames: {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-${take(zoneName, 32)}'), 64)
  scope: coreDnsZoneRg
  params: {
    zoneName: zoneName
  }
}]

// Link the private DNS Zones to the virtual network
module corePrivateDnsZonesLinkModule 'modules/privateDnsZoneVNetLink.bicep' = [for (zoneName, i) in corePrivateDnsZoneNames: {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-link-${take(zoneName, 29)}'), 64)
  scope: coreDnsZoneRg
  params: {
    dnsZoneName: zoneName
    vNetId: networkModule.outputs.vNetId
  }
}]

// Deploy UAMI
module uamiModule 'modules/uami.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami'), 64)
  scope: securityRg
  params: {
    location: location
    identityName: replace(namingStructure, '{rtype}', 'uami')
  }
}

// Deploy KV and its private endpoint
module keyVaultShortNameModule 'common-modules/shortname.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-shortname'), 64)
  scope: securityRg
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'kv'
    sequence: sequence
    workloadName: workloadName
  }
}

module keyVaultModule 'modules/keyVault/keyVault.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv'), 64)
  scope: securityRg
  params: {
    location: location
    keyVaultName: keyVaultShortNameModule.outputs.shortName
    namingStructure: namingStructure
    privateEndpointSubnetId: networkModule.outputs.createdSubnets.privateEndpoints.id
    privateDnsZoneId: corePrivateDnsZonesModule[1].outputs.zoneId
    privateEndpointResourceGroupName: networkingRg.name
    tags: tags
  }
}

// Create encryption keys for Container Registry, PostgreSQL, and storage accounts
// Must create new keys each time because key expiration dates can't be updated with Bicep/ARM
var keyNames = {
  postgres: {
    name: 'postgres'
  }
  cr: {
    name: 'cr'
  }
  st: {
    name: 'st'
  }
}

module keyVaultKeyWrapperModule 'modules/keyVault/keyVault-keyWrapper.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-keywrap'), 64)
  scope: securityRg
  params: {
    deploymentNameStructure: deploymentNameStructure
    keyNames: keyNames
    keyVaultName: keyVaultModule.outputs.keyVaultName
    keyNameRandomInit: keyNameRandomInit
  }
}

module rolesModule 'common-modules/roles.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'roles-main'), 64)
  scope: subscription()
}

// Assign RBAC for UAMI to KV
// * Key Vault Crypto User
module uamiKeyVaultRbacModule 'modules/roleAssignments/roleAssignment-kv.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-rbac-uami'), 64)
  scope: securityRg
  params: {
    kvName: keyVaultModule.outputs.keyVaultName
    principalId: uamiModule.outputs.principalId
    roleDefinitionId: rolesModule.outputs.roles['Key Vault Crypto User']
  }
}

// Deploy Container Registry
module crShortNameModule 'common-modules/shortname.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'cr-shortname'), 64)
  scope: containerRegRg
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'cr'
    sequence: sequence
    workloadName: workloadName
  }
}

module crModule 'modules/cr.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'cr'), 64)
  scope: containerRegRg
  params: {
    location: location
    crName: crShortNameModule.outputs.shortName
    // CR will autorotate to use the latest key version
    keyUri: keyVaultKeyWrapperModule.outputs.createdKeys.cr.uriWithoutVersion
    namingStructure: namingStructure
    privateDnsZoneId: corePrivateDnsZonesModule[0].outputs.zoneId
    privateEndpointResourceGroupName: networkingRg.name
    uamiId: uamiModule.outputs.id
    uamiApplicationId: uamiModule.outputs.applicationId
    privateEndpointSubnetId: networkModule.outputs.createdSubnets.privateEndpoints.id
  }
  dependsOn: [
    uamiKeyVaultRbacModule
  ]
}

// Deploy PG flexible server
module postgresqlModule 'modules/postgresql.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'postgresql'), 64)
  scope: dataRg
  params: {
    location: location
    dbAdminPassword: dbAdminPassword
    postgresqlVersion: postgresqlVersion
    privateDnsZoneId: pgDnsZonesModule.outputs.zoneId
    serverName: postgresqlShortNameModule.outputs.shortName
    subnetId: networkModule.outputs.createdSubnets.postgresql.id
    uamiId: uamiModule.outputs.id

    // Enable AAD authentication to DB server
    // If either of these values are empty, AAD auth will not be enabled
    aadAdminGroupName: dbAadGroupName
    aadAdminGroupObjectId: dbAadGroupObjectId

    databaseName: databaseName

    // PostgreSQL Flexible Server requires the version number with the key (no auto-rotate)
    customerEncryptionKeyUri: keyVaultKeyWrapperModule.outputs.createdKeys.postgres.uriWithVersion
    tags: tags
  }
  dependsOn: [
    uamiKeyVaultRbacModule
  ]
}

// Deploy Bastion
module bastionModule 'modules/bastion.bicep' = if (deployBastion) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'bas'), 64)
  scope: networkingRg
  params: {
    location: location
    bastionSubnetId: networkModule.outputs.createdSubnets.AzureBastionSubnet.id
    namingStructure: namingStructure
    tags: tags
  }
}

// Define Key Vault secrets for app settings
var kvSecrets = {
  dbAppSvcLogin: {
    name: 'ApiAppSvc-DBUSER'
    description: 'Database login name used by App Service'
    value: dbAppSvcLogin
  }
  dbAppSvcPassword: {
    name: 'ApiAppSvc-DBPASS'
    description: 'Database password used by App Service'
    value: dbAppSvcPassword
  }
  emailToken: {
    name: 'ApiAppSvc-EMAILTOKEN'
    description: 'Email token used by App Service for authentication to email service'
    value: emailToken
  }
}
// Create Key Vault secrets for app settings
module keyVaultSecretsModule 'modules/keyVault/keyVault-secrets.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-secrets'), 64)
  scope: securityRg
  params: {
    keyVaultName: keyVaultModule.outputs.keyVaultName
    secrets: kvSecrets
  }
}

// Create a custom object with the app setting names and their secret names
var apiSecretSettings = {
  DB_USER: kvSecrets.dbAppSvcLogin.name
  DB_PASS: kvSecrets.dbAppSvcPassword.name
  EMAIL_TOKEN: kvSecrets.emailToken.name
}

// Create Key Vault reference strings for use in App Service settings for each of the secrets
module keyVaultRefsModule './common-modules/appSvcKeyVaultRefs.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kvSecretRef'), 64)
  scope: securityRg
  params: {
    keyVaultName: keyVaultModule.outputs.keyVaultName
    appSettingSecretNames: apiSecretSettings
  }
}

// Use the output of the KV secret reference module to create a custom object in the same shape as expected for app settings
var apiAppKeyVaultRefSettings = reduce(keyVaultRefsModule.outputs.keyVaultRefs, {}, (cur, next) => union(cur, next))

// Manually list additional application settings that couldn't be provided as parameters
var additionalApiAppSettings = {
  DB_HOST: postgresqlModule.outputs.dbFqdn
  DB_NAME: databaseName
}

// Merge the app settings parameter value with the KV secret references
var actualApiAppSettings = union(apiAppSettings, apiAppKeyVaultRefSettings, additionalApiAppSettings)

// Determine which subnets can access the app services
var allowAccessSubnetIds = [
  networkModule.outputs.createdSubnets.appgw.id
]
var allowAccessDefaultSubnetId = deployDefaultSubnet ? [
  networkModule.outputs.createdSubnets.default.id
] : []
var actualAllowAccessSubnetIds = concat(allowAccessSubnetIds, allowAccessDefaultSubnetId)

// Deploy App Service
// This module creates the App Service Plan, two App Services, and necessary RBAC
module appSvcModule 'modules/appSvc/appSvc-main.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'appSvc'), 64)
  scope: appsRg
  params: {
    location: location
    apiContainerImageName: apiContainerImageName
    appContainerImageName: appContainerImageName
    crName: crModule.outputs.crName
    crResourceGroupName: containerRegRg.name
    deploymentNameStructure: deploymentNameStructure
    keyVaultName: keyVaultModule.outputs.keyVaultName
    kvResourceGroupName: securityRg.name
    namingStructure: namingStructure
    subnetId: networkModule.outputs.createdSubnets.apps.id
    apiAppSettings: actualApiAppSettings
    webAppSettings: webAppSettings
    appInsights: {
      instrumentationKey: appInsightsModule.outputs.instrumentationKey
      connectionString: appInsightsModule.outputs.connectionString
    }
    allowAccessSubnetIds: actualAllowAccessSubnetIds
    logAnalyticsWorkspaceId: logModule.outputs.workspaceId
    tags: tags
  }
  dependsOn: [
    keyVaultSecretsModule
  ]
}

output apiAppSvcName string = appSvcModule.outputs.apiAppSvcName
output webAppSvcName string = appSvcModule.outputs.webAppSvcName
output appsRgName string = appsRg.name
output crName string = crModule.outputs.crName
output crResourceGroupName string = containerRegRg.name

// Deploy APP GW with App Services backends
module appGwModule 'modules/appGw.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'appgw'), 64)
  scope: networkingRg
  params: {
    location: location
    namingStructure: namingStructure
    subnetId: networkModule.outputs.createdSubnets.appgw.id
    uamiId: uamiModule.outputs.id
    appsRgName: appsRg.name
    backendAppSvcs: [
      {
        name: 'api'
        appSvcName: appSvcModule.outputs.apiAppSvcName
        hostName: apiHostName
      }
      {
        name: 'web'
        appSvcName: appSvcModule.outputs.webAppSvcName
        hostName: webHostName
      }
    ]
    tags: tags
  }
}

output keyVaultKeysUniqueNameSuffix string = keyVaultKeyWrapperModule.outputs.keyNameUniqueSuffix

// Add Storage account with CMK with public access enabled
module publicStorageAccountNameModule 'common-modules/shortname.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'st-web-name'), 64)
  scope: dataRg
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'st'
    sequence: sequence
    // Hyphen added here for clarity, but it will be removed by the module
    workloadName: '${workloadName}-web'
  }
}

module publicStorageAccountModule 'modules/storageAccount.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'st-pub'), 64)
  scope: dataRg
  params: {
    location: location
    blobContainerName: '$web'
    storageAccountName: publicStorageAccountNameModule.outputs.shortName
    keyVaultUrl: keyVaultModule.outputs.keyVaultUrl
    keyName: keyVaultKeyWrapperModule.outputs.createdKeys.st.name
    uamiId: uamiModule.outputs.id
    allowBlobPublicAccess: true
    privateEndpointResourceGroupName: networkingRg.name
    tags: tags
  }
  dependsOn: [
    uamiKeyVaultRbacModule
  ]
}

output publicStorageAccountName string = publicStorageAccountNameModule.outputs.shortName
output publicStorageAccountResourceGroupName string = dataRg.name

// LATER: CDN for custom domain for storage account

// Create a storage account to save Log Analytics queries
module logQueryStorageAccountNameModule 'common-modules/shortname.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'st-log-name'), 64)
  scope: securityRg
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'st'
    sequence: sequence
    // Hyphen added here for clarity, but it will be removed by the module
    workloadName: '${workloadName}-log'
  }
}

module logQueryStorageAccountModule 'modules/storageAccount.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'st-log'), 64)
  scope: securityRg
  params: {
    location: location
    tags: tags
    blobContainerName: 'saved-queries'
    keyVaultUrl: keyVaultModule.outputs.keyVaultUrl
    keyName: keyVaultKeyWrapperModule.outputs.createdKeys.st.name
    storageAccountName: logQueryStorageAccountNameModule.outputs.shortName
    uamiId: uamiModule.outputs.id
    privateEndpoint: true
    privateDnsZoneId: corePrivateDnsZonesModule[2].outputs.zoneId
    privateEndpointResourceGroupName: networkingRg.name
    privateEndpointSubnetId: networkModule.outputs.createdSubnets.privateEndpoints.id
    namingStructure: namingStructure
  }
  dependsOn: [
    uamiKeyVaultRbacModule
  ]
}

// Add Log Analytics workspace
module logModule 'modules/log.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'log'), 64)
  scope: securityRg
  params: {
    location: location
    namingStructure: namingStructure
    savedQueryStorageAccountName: logQueryStorageAccountModule.outputs.storageAccountName
    tags: tags
  }
}

// Create an Application Insights instance linked to the Log Analytics Workspace
module appInsightsModule 'modules/appInsights.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'appi'), 64)
  scope: appsRg
  params: {
    location: location
    appInsightsName: replace(namingStructure, '{rtype}', 'appi')
    logAnalyticsWorkspaceId: logModule.outputs.workspaceId
  }
}

output encryptionKeyNames object = keyVaultKeyWrapperModule.outputs.createdKeys

// Output HOSTS information
var peNics = concat(keyVaultModule.outputs.nicIds, crModule.outputs.nicIds, logQueryStorageAccountModule.outputs.nicIds)

module peIpsModule 'modules/privateEndpoints-getIp.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'pe-ip'), 64)
  scope: networkingRg
  params: {
    deploymentNameStructure: deploymentNameStructure
    privateEndpointNicIds: peNics
  }
}

output privateIps array = peIpsModule.outputs.privateIps

// This will only output values on initial deployment. Incremental deployments will not include these values.
output customDnsConfigs array = concat(keyVaultModule.outputs.peCustomDnsConfigs, crModule.outputs.customDnsConfigs, logQueryStorageAccountModule.outputs.customDnsConfigs)

// NOT COVERED HERE
// * SOME RBAC
// * CONTAINER IMAGE DEPLOYMENT
// * AUDITING / DIAGNOSTIC SETTINGS
// * CUSTOM DOMAIN NAMES
// * TLS FOR APP GW
// * ROUTE TABLE FOR FW
// * KEY ROTATION FOR POSTGRESQL
// * POLICY EXEMPTIONS FOR WEB STORAGE ACCOUNT
