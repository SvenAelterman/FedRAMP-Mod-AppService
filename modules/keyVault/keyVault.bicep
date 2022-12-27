param location string
param namingStructure string
param keyVaultName string
param privateEndpointSubnetId string
param privateDnsZoneId string

param privateEndpointResourceGroupName string = resourceGroup().name
param allowPublicAccess bool = false
param tags object = {}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    // Required to be true for FedRAMP and required for PostgreSQL
    enablePurgeProtection: true
    enableSoftDelete: true
    // 90 days is required for PostgreSQL CMK
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    tenantId: subscription().tenantId
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: allowPublicAccess ? 'Allow' : 'Deny'
    }
    publicNetworkAccess: allowPublicAccess ? 'Enabled' : 'Disabled'
  }
  tags: tags
}

// Set resource lock on KV
resource kvLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: replace(namingStructure, '{rtype}', 'kv-lock')
  scope: keyVault
  properties: {
    level: 'CanNotDelete'
  }
}

// Deploy a private endpoint for the Key Vault
var peName = replace(namingStructure, '{rtype}', 'pe-kv')

resource peRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: privateEndpointResourceGroupName
  scope: subscription()
}

module pe '../privateEndpoint.bicep' = {
  name: 'kv-pe'
  scope: peRg
  params: {
    location: location
    peName: peName
    privateDnsZoneId: privateDnsZoneId
    privateEndpointSubnetId: privateEndpointSubnetId
    privateLinkServiceId: keyVault.id
    connectionGroupIds: [
      'vault'
    ]
    tags: tags
  }
}

output keyVaultName string = keyVault.name
output keyVaultUrl string = keyVault.properties.vaultUri
output peCustomDnsConfigs array = pe.outputs.peCustomDnsConfigs
output nicIds array = pe.outputs.nicIds
