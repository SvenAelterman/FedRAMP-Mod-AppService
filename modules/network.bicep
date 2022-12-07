param location string
param subnetDefs object
param deploymentNameStructure string
param vNetAddressPrefix string
param namingStructure string

param tags object = {}

module networkSecurityModule 'networkSecurity.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'networkSecurity')
  params: {
    subnetDefs: subnetDefs
    deploymentNameStructure: deploymentNameStructure
    namingStructure: namingStructure
    location: location
  }
}

var vNetName = replace(namingStructure, '{rtype}', 'vnet')

// This is the parent module to deploy a VNet with subnets and output the subnets with their IDs as a custom object
module vNetModule 'vnet.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'vnet')
  params: {
    location: location
    subnetDefs: subnetDefs
    vnetName: vNetName
    vnetAddressPrefix: vNetAddressPrefix
    networkSecurityGroups: networkSecurityModule.outputs.nsgIds
    tags: tags
  }
}

output createdSubnets object = reduce(vNetModule.outputs.actualSubnets, {}, (cur, next) => union(cur, next))
output vNetId string = vNetModule.outputs.vNetId
