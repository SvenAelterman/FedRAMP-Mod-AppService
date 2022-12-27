param location string
param crName string
@description('The Key Vault key to use for encryption, without version')
param keyUri string
param uamiApplicationId string
param uamiId string
param namingStructure string
param privateEndpointResourceGroupName string
param privateDnsZoneId string
param privateEndpointSubnetId string

param tags object = {}

resource cr 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' = {
  name: crName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    anonymousPullEnabled: false
    networkRuleBypassOptions: 'AzureServices'
    encryption: {
      status: 'enabled'
      keyVaultProperties: {
        keyIdentifier: keyUri
        identity: uamiApplicationId
      }
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  tags: tags
}

var peName = replace(namingStructure, '{rtype}', 'pe-cr')

resource peRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: privateEndpointResourceGroupName
  scope: subscription()
}

module pe 'privateEndpoint.bicep' = {
  name: 'cr-pe'
  scope: peRg
  params: {
    location: location
    peName: peName
    privateDnsZoneId: privateDnsZoneId
    privateEndpointSubnetId: privateEndpointSubnetId
    privateLinkServiceId: cr.id
    connectionGroupIds: [
      'registry'
    ]
    tags: tags
  }
}

output crName string = cr.name
output acrLoginServer string = cr.properties.loginServer
output customDnsConfigs array = pe.outputs.peCustomDnsConfigs
output nicIds array = pe.outputs.nicIds
