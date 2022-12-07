param keyName string
param keyVaultName string

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

resource newKey 'Microsoft.KeyVault/vaults/keys@2022-07-01' = {
  name: keyName
  parent: keyVault
  properties: {
    kty: algorithm
    keySize: keySize
    rotationPolicy: {
      attributes: {
        // Expire the key after 1 year
        expiryTime: keyValidityPeriod
      }
      lifetimeActions: [
        // Notify (using Event Grid) before key expires
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
    exp: dateTimeToEpoch(expiryDateTime)
  }
}

output keyUri string = newKey.properties.keyUriWithVersion
output keyUriNoVersion string = newKey.properties.keyUri
