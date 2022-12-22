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

param postgresqlVersion string
@secure()
param dbAdminPassword string

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
//var rgNamingStructure = replace(thisNamingStructure, '{rtype}', 'rg')

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

// resource storageRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
//   name: replace(rgNamingStructure, '{wloadname}', '${workloadName}-storage')
//   location: location
//   tags: tags
// }

resource coreDnsZoneRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
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
    serviceEndpoints: []
    delegation: ''
    securityRules: loadJsonContent('content/nsgrules/appGw.json')
  }
}

var defaultSubnet = deployDefaultSubnet ? {
  default: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (4 * subnetBoundary)))}/${subnetCidr}'
    serviceEndpoints: []
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
  'privatelink.azurecr.io'
  'privatelink.vaultcore.azure.net'
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

module keyVaultModule 'modules/keyVault.bicep' = {
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

// Create encryption keys for CR, ACI, PG
// Must create new keys each time because key expiration dates can't be updated with Bicep/ARM
var keyNameUniqueSuffix = uniqueString(keyNameRandomInit)
var keyNames = [
  'postgres-${keyNameUniqueSuffix}'
  'cr-${keyNameUniqueSuffix}'
  'st-${keyNameUniqueSuffix}'
]

module keyVaultKeysModule 'modules/keyVault-key.bicep' = [for keyName in keyNames: {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-key-${keyName}'), 64)
  scope: securityRg
  params: {
    keyName: keyName
    keyVaultName: keyVaultModule.outputs.keyVaultName
  }
}]

// Assign RBAC for UAMI to KV
// * Key Vault Crypto User
module uamiKeyVaultRbacModule 'modules/keyVault-rbac.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-rbac-uami'), 64)
  scope: securityRg
  params: {
    keyVaultName: keyVaultModule.outputs.keyVaultName
    principalId: uamiModule.outputs.principalId
    roleName: 'Key Vault Crypto User'
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
    keyUri: keyVaultKeysModule[1].outputs.keyUriNoVersion
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

    customerEncryptionKeyUri: keyVaultKeysModule[0].outputs.keyUri
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

// Deploy APP GW with an empty backend pool
module appGwModule 'modules/appGw.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'appgw'), 64)
  scope: networkingRg
  params: {
    location: location
    namingStructure: namingStructure
    subnetId: networkModule.outputs.createdSubnets.appgw.id
    uamiId: uamiModule.outputs.id
  }
}

output keyVaultKeysUniqueNameSuffix string = keyNameUniqueSuffix

// Add Storage account with CMK with public access enabled
module publicStorageAccountNameModule 'common-modules/shortname.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'st-pub-name'), 64)
  scope: dataRg
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'st'
    sequence: sequence
    // Hyphen added here for clarity, but it will be removed by the module
    workloadName: '${workloadName}-pub'
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
    keyName: keyVaultKeysModule[2].outputs.keyName
    uamiId: uamiModule.outputs.id
    tags: tags
  }
  dependsOn: [
    uamiKeyVaultRbacModule
  ]
}

// TODO: CDN for custom domain for storage account

output publicStorageAccountName string = publicStorageAccountNameModule.outputs.shortName
output publicStorageAccountResourceGroupName string = dataRg.name

// TODO: Add storage account with CMK for saved queries in LA

// Add Log Analytics workspace
module logModule 'modules/log.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'log'), 64)
  scope: securityRg
  params: {
    location: location
    namingStructure: namingStructure
    tags: tags
  }
}

// TODO: Deploy App Service
// If so:
// Add App Insights?
// Add Key Vault Secrets for database password, etc.
// Update delegation of "apps" subnet

// NOT COVERED HERE
// * STORAGE ACCOUNT FOR SAVED QUERIES IN LAW
// * SOME RBAC
// * CONTAINER IMAGE DEPLOYMENT
// * AUDITING / DIAGNOSTIC SETTINGS
// * CUSTOM DOMAIN NAMES
// * TLS FOR APP GW
// * ROUTE TABLE FOR FW
// * KEY ROTATION FOR POSTGRESQL
