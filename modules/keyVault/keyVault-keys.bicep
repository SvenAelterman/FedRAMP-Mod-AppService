param keyNames object
param keyVaultName string
param keyNameUniqueSuffix string

param keyValidityPeriod string = 'P2Y'
@description('The time period before key expiration to send a notification of expiration.')
param notifyPeriod string = 'P30D'
@description('The time period before key expiration to renew the key.')
param autoRotatePeriod string = 'P60D'
param expiryDateTime string = dateTimeAdd(utcNow(), keyValidityPeriod)

// These defaults should be kept for keys used to encrypt Azure services' storage
param keySize int = 2048
param algorithm string = 'RSA'

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

// This sorts alphabetically
var keyNamesArray = items(keyNames)

resource newKey 'Microsoft.KeyVault/vaults/keys@2022-07-01' = [for keyName in keyNamesArray: {
  name: '${keyName.value.name}-${keyNameUniqueSuffix}'
  parent: keyVault
  properties: {
    attributes: {
      exp: dateTimeToEpoch(expiryDateTime)
    }
    kty: algorithm
    keySize: keySize
    rotationPolicy: {
      attributes: {
        // Expire the key after 1 year
        expiryTime: keyValidityPeriod
      }
      lifetimeActions: [
        // Notify (using Event Grid) before key expires
        // LATER: Set up Event Grid subscription?
        // If the notify period is less than the rotate period, notification shouldn't be sent
        {
          action: {
            type: 'notify'
          }
          trigger: {

            timeBeforeExpiry: notifyPeriod
          }
        }
        // Rotate the key before it expires
        {
          action: {
            type: 'rotate'
          }
          trigger: {
            timeBeforeExpiry: autoRotatePeriod
          }
        }
      ]
    }
  }
}]

resource keyRes 'Microsoft.KeyVault/vaults/keys@2022-07-01' existing = [for keyName in keyNamesArray: {
  name: '${keyName.value.name}-${keyNameUniqueSuffix}'
  parent: keyVault
}]

output actualKeys array = [for i in range(0, length(keyNamesArray)): {
  '${keyNamesArray[i].key}': {
    name: keyRes[i].name
    uriWithVersion: keyRes[i].properties.keyUriWithVersion
    uriWithoutVersion: keyRes[i].properties.keyUri
  }
}]
