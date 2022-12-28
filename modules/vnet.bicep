param location string
param vnetName string
param subnetDefs object
param vnetAddressPrefix string
@description('The NSG array must have the NSGs sorted in the same way items(subnetDefs) will be sorted.')
param networkSecurityGroups array

param tags object = {}

// This will sort the subnets alphabetically by name
var subnetDefsArray = items(subnetDefs)

resource vnet 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    // Loop through each subnet in the array
    subnets: [for (subnet, i) in subnetDefsArray: {
      // The name of the subnet (property name) became the key property
      name: subnet.key
      properties: {
        // All other properties are child properties of the value property
        addressPrefix: subnet.value.addressPrefix
        serviceEndpoints: subnet.value.serviceEndpoints
        delegations: empty(subnet.value.delegation) ? null : [
          {
            name: 'delegation'
            properties: {
              serviceName: subnet.value.delegation
            }
          }
        ]
        networkSecurityGroup: {
          id: networkSecurityGroups[i]
        }
        routeTable: empty(subnet.value.routeTable) ? null : {
          id: subnet.value.routeTable
        }
      }
    }]
  }
  tags: tags
}

// Retrieve the subnets as an array of existing resources
// This is important because we need to ensure subnet properties match the name
resource subnetRes 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' existing = [for subnet in subnetDefsArray: {
  name: subnet.key
  parent: vnet
}]

// Outputs in the order of the virtual network, which is not necessarily the order of subnetDefsArray
output actualSubnets array = [for i in range(0, length(subnetDefsArray)): {
  '${subnetRes[i].name}': {
    id: subnetRes[i].id
    addressPrefix: subnetRes[i].properties.addressPrefix
    // Add as many additional subnet properties as needed downstream
  }
}]

output vNetId string = vnet.id
