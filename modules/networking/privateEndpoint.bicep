param peName string
param location string
param privateEndpointSubnetId string
param privateDnsZoneId string
param privateLinkServiceId string
param connectionGroupIds array

param tags object = {}

resource pe 'Microsoft.Network/privateEndpoints@2022-05-01' = {
  name: peName
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: peName
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: connectionGroupIds
        }
      }
    ]
  }
  tags: tags
}

resource peDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = {
  name: 'default'
  parent: pe
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output peCustomDnsConfigs array = pe.properties.customDnsConfigs
output nicIds array = map(pe.properties.networkInterfaces, nic => nic.id)
