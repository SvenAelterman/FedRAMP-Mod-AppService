param keyVaultName string

@secure()
param secrets object

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

var secretsArray = items(secrets)

resource secret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = [for secret in secretsArray: {
  name: secret.value.name
  parent: keyVault
  properties: {
    contentType: secret.value.description
    value: secret.value.value
  }
}]
