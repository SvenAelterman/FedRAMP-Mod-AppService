targetScope = 'subscription'

@allowed([
  'eastus2'
  'eastus'
])
param location string
@allowed([
  'test'
  'demo'
  'prod'
])
param environment string
param workloadName string

param postgresqlVersion string
@secure()
param dbAdminPassword string

param vNetAddressSpace string = '10.24.{octet3}.0'
param vNetCidr string = '16'
param subnetCidr string = '24'

// Optional parameters
param dbAadGroupObjectId string = ''
param dbAadGroupName string = ''
param deployBastion bool = false
param tags object = {}
param sequence int = 1
param namingConvention string = '{rtype}-{wloadname}-{env}-{loc}-{seq}'
param deploymentTime string = utcNow()
param keyNameRandomInit string = utcNow()

var sequenceFormatted = format('{0:00}', sequence)

var deploymentNameStructure = '${workloadName}-${environment}-{rtype}-${deploymentTime}'
// Naming structure only needs the resource type ({rtype}) replaced
var thisNamingStructure = replace(replace(replace(namingConvention, '{env}', environment), '{loc}', location), '{seq}', sequenceFormatted)
var namingStructure = replace(thisNamingStructure, '{wloadname}', workloadName)
var rgNamingStructure = replace(thisNamingStructure, '{rtype}', 'rg')

// Create resource groups
resource networkingRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(rgNamingStructure, '{wloadname}', 'networking')
  location: location
}

resource containersRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(rgNamingStructure, '{wloadname}', 'containers')
  location: location
}

resource databaseRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(rgNamingStructure, '{wloadname}', 'database')
  location: location
}

resource securityRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(rgNamingStructure, '{wloadname}', 'security')
  location: location
}

// Create virtual network and subnets
var subnets = {
  default: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet3}', '0')}/${subnetCidr}'
    serviceEndpoints: []
    delegation: ''
    securityRules: loadJsonContent('content/nsgrules/default.json')
  }
  privateEndpoints: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet3}', '1')}/${subnetCidr}'
    serviceEndpoints: []
    delegation: ''
    securityRules: []
  }
  postgresql: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet3}', '2')}/${subnetCidr}'
    serviceEndpoints: []
    delegation: 'Microsoft.DBforPostgreSQL/flexibleServers'
    securityRules: loadJsonContent('content/nsgrules/postgresql.json')
  }
  aci: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet3}', '3')}/${subnetCidr}'
    serviceEndpoints: []
    delegation: 'Microsoft.ContainerInstance/containerGroups'
    securityRules: []
  }
  appgw: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet3}', '255')}/${subnetCidr}'
    serviceEndpoints: []
    delegation: ''
    securityRules: loadJsonContent('content/nsgrules/appGw.json')
  }
}
var AzureBastionSubnet = deployBastion ? {
  AzureBastionSubnet: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet3}', '254')}/${subnetCidr}'
    serviceEndpoints: []
    delegation: ''
    securityRules: loadJsonContent('content/nsgrules/bastion.json')
  }
} : {}

var subnetsToDeploy = union(subnets, AzureBastionSubnet)

// Create the basic network resources: Virtual Network + subnets, Network Security Groups
module networkModule 'modules/network.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'network'), 64)
  scope: networkingRg
  params: {
    location: location
    deploymentNameStructure: deploymentNameStructure
    subnetDefs: subnetsToDeploy
    vNetAddressPrefix: '${replace(vNetAddressSpace, '{octet3}', '0')}/${vNetCidr}'
    namingStructure: namingStructure
    tags: tags
  }
}

module postgresqlShortNameModule 'common-modules/shortname.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'pg-name'), 64)
  scope: databaseRg
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'pg'
    sequence: sequence
    workloadName: workloadName
  }
}

//var postgresqlServerName = replace(namingStructure, '{rtype}', 'pg')
// var postgresqlDnsZoneName = '${postgresqlServerName}.private.postgres.database.azure.com'
// // Deploy private DNS zones
// var privateDnsZoneNames = [
//   postgresqlDnsZoneName
// ]

param coreSubscriptionId string

resource coreDnsZoneRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  name: 'UHealth_IT_Core-RG'
  scope: subscription(coreSubscriptionId)
}

var corePrivateDnsZoneNames = [
  'privatelink.azurecr.io'
  'privatelink.vaultcore.azure.net'
]

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

module privateDnsZonesModule 'modules/privateDnsZone.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-pg'), 64)
  scope: networkingRg
  params: {
    zoneName: '${postgresqlShortNameModule.outputs.shortName}.private.postgres.database.azure.com'
    tags: tags
  }
}

// Link the private DNS Zones to the virtual network
module privateDnsZonesLinkModule 'modules/privateDnsZoneVNetLink.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-link-pg'), 64)
  scope: networkingRg
  params: {
    dnsZoneName: '${postgresqlShortNameModule.outputs.shortName}.private.postgres.database.azure.com'
    vNetId: networkModule.outputs.vNetId
  }
}

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
// HACK: Creating new keys each time
var keyNameUniqueSuffix = uniqueString(keyNameRandomInit)
var keyNames = [
  'postgres-${keyNameUniqueSuffix}'
  'cr-${keyNameUniqueSuffix}'
  'aci-1-${keyNameUniqueSuffix}'
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
  scope: containersRg
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
  scope: containersRg
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
  scope: databaseRg
  params: {
    location: location
    dbAdminPassword: dbAdminPassword
    postgresqlVersion: postgresqlVersion
    privateDnsZoneId: privateDnsZonesModule.outputs.zoneId
    serverName: postgresqlShortNameModule.outputs.shortName
    subnetId: networkModule.outputs.createdSubnets.postgresql.id
    uamiId: uamiModule.outputs.id

    // Enable AAD authentication to DB server
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

// NOT COVERED HERE
// * LOG ANALYTICS WORKSPACE (CREATE DEDICATED CLUSTER?)
// * + STORAGE ACCOUNT FOR SAVED QUERIES
// * SOME RBAC
// * CONTAINER IMAGE DEPLOYMENT
// * AUDITING
// * CUSTOM DOMAIN NAMES
// * TLS FOR APP GW
// * ROUTE TABLE FOR FW
// * KEY ROTATION FOR POSTGRESQL
