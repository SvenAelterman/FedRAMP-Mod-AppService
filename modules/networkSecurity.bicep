/* Parent module for NSGs */
param subnetDefs object
param deploymentNameStructure string
param namingStructure string

param location string = resourceGroup().location

var subnetArray = items(subnetDefs)

// Create NSGs
module nsgsModule 'nsg.bicep' = [for (subnet, i) in items(subnetDefs): {
  name: replace(deploymentNameStructure, '{rtype}', 'nsg-${subnet.key}')
  params: {
    location: location
    nsgName: replace(namingStructure, '{rtype}', 'nsg-${subnet.key}')
    securityRules: subnet.value.securityRules
  }
}]

output nsgIds array = [for i in range(0, length(subnetArray)): nsgsModule[i].outputs.nsgId]
