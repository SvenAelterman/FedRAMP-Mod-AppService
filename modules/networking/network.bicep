param location string
param subnetDefs object
param deploymentNameStructure string
param vNetAddressPrefix string
param namingStructure string

param tags object = {}

// Create a Network Security Group for each subnet
module networkSecurityModule 'networkSecurity.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'networkSecurity'), 64)
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
  name: take(replace(deploymentNameStructure, '{rtype}', 'vnet'), 64)
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
