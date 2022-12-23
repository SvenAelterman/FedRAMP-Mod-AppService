param keyNames object
param deploymentNameStructure string
param keyVaultName string

param keyNameRandomInit string = utcNow()

var keyNameUniqueSuffix = uniqueString(keyNameRandomInit)

module keyVaultKeysModule 'keyVault-keys.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-keys'), 64)
  params: {
    keyNames: keyNames
    keyVaultName: keyVaultName
    keyNameUniqueSuffix: keyNameUniqueSuffix
  }
}

output keyNameUniqueSuffix string = keyNameUniqueSuffix
output createdKeys object = reduce(keyVaultKeysModule.outputs.actualKeys, {}, (cur, next) => union(cur, next))
