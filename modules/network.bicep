param vNetName string
param location string
param subnetDefs object
param deploymentNameStructure string
param vNetAddressPrefix string

param tags object = {}

// This is the parent module to deploy a VNet with subnets and output the subnets with their IDs as a custom object
module vnetModule 'vnet.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'vnet')
  params: {
    location: location
    subnetDefs: subnetDefs
    vnetName: vNetName
    vnetAddressPrefix: vNetAddressPrefix
    tags: tags
  }
}

output createdSubnets object = reduce(vnetModule.outputs.actualSubnets, {}, (cur, next) => union(cur, next))
output vNetId string = vnetModule.outputs.vNetId
