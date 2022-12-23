param keyVaultName string

@secure()
param secrets object

// This is not a secret value
#disable-next-line secure-secrets-in-params
param secretValidityPeriod string = 'P2Y'

param expiryDateTime string = dateTimeAdd(utcNow(), secretValidityPeriod)

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
    attributes: {
      enabled: true
      exp: dateTimeToEpoch(expiryDateTime)
    }
  }
}]
