param vNetId string
param dnsZoneName string

param registrationEnabled bool = false

// Get a reference to the DNS zone to link
resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: dnsZoneName
}

// Create the link with the specified VNet
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: uniqueString(vNetId)
  parent: dnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vNetId
    }
    registrationEnabled: registrationEnabled
  }
}
