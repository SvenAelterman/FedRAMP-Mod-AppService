param keyName string
param keyVaultName string

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

resource newKey 'Microsoft.KeyVault/vaults/keys@2022-07-01' = {
  name: keyName
  parent: keyVault
  properties: {
    kty: 'RSA'
    keySize: 2048
  }
}

output keyUri string = newKey.properties.keyUriWithVersion
output keyUriNoVersion string = newKey.properties.keyUri
