param nicId string

var nicName = last(split(nicId, '/'))

resource nic 'Microsoft.Network/networkInterfaces@2022-05-01' existing = {
  name: nicName
}

output ipAddresses array = map(nic.properties.ipConfigurations, ipc => ipc.properties.privateIPAddress)
