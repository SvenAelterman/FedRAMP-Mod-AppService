param location string
param storageAccountName string
param blobContainerName string
param uamiId string
param keyName string
param keyVaultUrl string
param allowBlobPublicAccess bool = false
param tags object

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_GRS'
  }
  properties: {
    // This does not need to be enable for static websites support
    // Ref: https://learn.microsoft.com/azure/storage/blobs/storage-blob-static-website#impact-of-setting-the-access-level-on-the-web-container
    allowBlobPublicAccess: allowBlobPublicAccess
    defaultToOAuthAuthentication: true
    isHnsEnabled: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
    encryption: {
      requireInfrastructureEncryption: true
      keySource: 'Microsoft.Keyvault'
      identity: {
        userAssignedIdentity: uamiId
      }
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
        table: {
          enabled: true
          keyType: 'Account'
        }
        queue: {
          enabled: true
          keyType: 'Account'
        }
      }
      keyvaultproperties: {
        keyname: keyName
        keyvaulturi: keyVaultUrl
      }
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  tags: tags
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2021-09-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    containerDeleteRetentionPolicy: {
      days: 7
      enabled: true
    }
  }
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-09-01' = {
  name: blobContainerName
  parent: blobServices
  properties: {
  }
}

output storageAccountName string = storageAccount.name
