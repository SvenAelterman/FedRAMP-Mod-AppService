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
  }
  privateEndpoints: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet3}', '1')}/${subnetCidr}'
    serviceEndpoints: []
    delegation: ''
  }
  postgresql: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet3}', '2')}/${subnetCidr}'
    serviceEndpoints: []
    delegation: 'Microsoft.DBforPostgreSQL/flexibleServers'
  }
  aci: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet3}', '3')}/${subnetCidr}'
    serviceEndpoints: []
    delegation: 'Microsoft.ContainerInstance/containerGroups'
  }
  appgw: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet3}', '255')}/${subnetCidr}'
    serviceEndpoints: []
    delegation: ''
  }
  AzureBastionSubnet: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet3}', '254')}/${subnetCidr}'
    serviceEndpoints: []
    delegation: ''
  }
}

module networkModule 'modules/network.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'network')
  scope: networkingRg
  params: {
    location: location
    deploymentNameStructure: deploymentNameStructure
    subnetDefs: subnets
    vNetAddressPrefix: '${replace(vNetAddressSpace, '{octet3}', '0')}/${vNetCidr}'
    vNetName: replace(namingStructure, '{rtype}', 'vnet')
    tags: tags
  }
}

// TODO: Create NSGs
// * App GW
// * Standard (no rules)

var postgresqlServerName = replace(namingStructure, '{rtype}', 'pg')
var postgresqlDnsZoneName = '${postgresqlServerName}.private.postgres.database.azure.com'
// Deploy private DNS zones
var privateDnsZoneNames = [
  postgresqlDnsZoneName
  'privatelink.azurecr.io'
  'privatelink.vaultcore.azure.net'
]

module privateDnsZonesModule 'modules/privateDnsZone.bicep' = [for zoneName in privateDnsZoneNames: {
  name: replace(deploymentNameStructure, '{rtype}', 'dns-${take(zoneName, 32)}')
  scope: networkingRg
  params: {
    zoneName: zoneName
    tags: tags
  }
}]

// Link the private DNS Zones to the virtual network
module privateDnsZonesLinkModule 'modules/privateDnsZoneVNetLink.bicep' = [for (zoneName, i) in privateDnsZoneNames: {
  name: replace(deploymentNameStructure, '{rtype}', 'dns-link-${take(zoneName, 29)}')
  scope: networkingRg
  params: {
    dnsZoneName: zoneName
    vNetId: networkModule.outputs.vNetId
  }
}]

// TODO: Deploy Log Analytics Workspace// (optional?)

// Deploy UAMI
module uamiModule 'modules/uami.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'uami')
  scope: securityRg
  params: {
    location: location
    identityName: replace(namingStructure, '{rtype}', 'uami')
  }
}

// Deploy KV and its private endpoint
module keyVaultShortNameModule 'common-modules/shortname.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'kv-shortname')
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
  name: replace(deploymentNameStructure, '{rtype}', 'kv')
  scope: securityRg
  params: {
    location: location
    keyVaultName: keyVaultShortNameModule.outputs.shortName
    namingStructure: namingStructure
    privateEndpointSubnetId: networkModule.outputs.createdSubnets.privateEndpoints.id
    privateDnsZoneId: privateDnsZonesModule[2].outputs.zoneId
    privateEndpointResourceGroupName: networkingRg.name
    tags: tags
  }
}

// Create encryption keys for CR, ACI, PG
var keyNames = [
  'postgres'
  'cr'
  'aci-1'
]

module keyVaultKeysModule 'modules/keyVault-key.bicep' = [for keyName in keyNames: {
  name: replace(deploymentNameStructure, '{rtype}', 'kv-key-${keyName}')
  scope: securityRg
  params: {
    keyName: keyName
    keyVaultName: keyVaultModule.outputs.keyVaultName
  }
}]

// Assign RBAC for UAMI to KV
// * Key Vault Crypto User
module uamiKeyVaultRbacModule 'modules/keyVault-rbac.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'kv-rbac-uami')
  scope: securityRg
  params: {
    keyVaultName: keyVaultModule.outputs.keyVaultName
    principalId: uamiModule.outputs.principalId
    roleName: 'Key Vault Crypto User'
  }
}

// Deploy CR
module crShortNameModule 'common-modules/shortname.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'cr-shortname')
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
  name: replace(deploymentNameStructure, '{rtype}', 'cr')
  scope: containersRg
  params: {
    location: location
    crName: crShortNameModule.outputs.shortName
    keyUri: keyVaultKeysModule[1].outputs.keyUriNoVersion
    namingStructure: namingStructure
    privateDnsZoneId: privateDnsZonesModule[1].outputs.zoneId
    privateEndpointResourceGroupName: networkingRg.name
    uamiId: uamiModule.outputs.id
    //uamiPrincipalId: uamiModule.outputs.principalId
    uamiApplicationId: uamiModule.outputs.applicationId
    privateEndpointSubnetId: networkModule.outputs.createdSubnets.privateEndpoints.id
  }
  dependsOn: [
    uamiKeyVaultRbacModule
  ]
}

// Deploy PG flexible server
module postgresqlModule 'modules/postgresql.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'postgresql')
  scope: databaseRg
  params: {
    location: location
    dbAdminPassword: dbAdminPassword
    postgresqlVersion: postgresqlVersion
    privateDnsZoneId: privateDnsZonesModule[0].outputs.zoneId //filter(privateDnsZonesModule, z => z.outputs.zoneName == postgresqlDnsZoneName)[0].outputs.zoneId
    serverName: postgresqlServerName
    subnetId: networkModule.outputs.createdSubnets.postgresql.id
    uamiId: uamiModule.outputs.id

    // TODO: Enable AAD auth when deployment is successful
    // aadAdminGroupName: dbAadGroupName
    // aadAdminGroupObjectId: dbAadGroupObjectId

    customerEncryptionKeyUri: keyVaultKeysModule[0].outputs.keyUri
    tags: tags
  }
  dependsOn: [
    uamiKeyVaultRbacModule
  ]
}

// Deploy ACI?

// Deploy Bastion
module bastionModule 'modules/bastion.bicep' = if (deployBastion) {
  name: replace(deploymentNameStructure, '{rtype}', 'bas')
  scope: networkingRg
  params: {
    location: location
    bastionSubnetId: networkModule.outputs.createdSubnets.AzureBastionSubnet.id
    namingStructure: namingStructure
    tags: tags
  }
}

// TODO: Deploy APP GW

output namingStructure string = namingStructure

// NOT COVERED HERE
// * RBAC
// * CONTAINER IMAGE DEPLOYMENT
// * AUDITING
