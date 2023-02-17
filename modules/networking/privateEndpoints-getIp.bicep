param privateEndpointNicIds array
param deploymentNameStructure string

module nicIpModule 'nic-getIp.bicep' = [for peNicId in privateEndpointNicIds: {
  name: take(replace(deploymentNameStructure, '{rtype}', 'pe-nic-ip-${last(split(peNicId, '/'))}'), 64)
  params: {
    nicId: peNicId
  }
}]

output privateIps array = [for i in range(0, length(privateEndpointNicIds)): nicIpModule[i].outputs.ipAddresses]
