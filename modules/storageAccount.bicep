param location string
param storageAccountName string
param blobContainerName string
param uamiId string
param keyName string
param keyVaultUrl string
param allowBlobPublicAccess bool = false
param tags object
@description('Must be specified to avoid deployment errors, even if no private endpoint will be created.')
param privateEndpointResourceGroupName string

param privateEndpoint bool = false
param privateDnsZoneId string = ''
param privateEndpointSubnetId string = ''
param namingStructure string = ''

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_GRS'
  }
  properties: {
    // This does not need to be enabled for static websites support
    // Ref: https://learn.microsoft.com/azure/storage/blobs/storage-blob-static-website#impact-of-setting-the-access-level-on-the-web-container
    allowBlobPublicAccess: privateEndpoint ? false : allowBlobPublicAccess
    defaultToOAuthAuthentication: true
    isHnsEnabled: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: privateEndpoint ? 'Disabled' : 'Enabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: privateEndpoint ? 'Deny' : 'Allow'
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

var peName = replace(namingStructure, '{rtype}', 'pe-st')

resource peRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (privateEndpoint) {
  name: privateEndpointResourceGroupName
  scope: subscription()
}

module pe 'privateEndpoint.bicep' = if (privateEndpoint) {
  name: 'st-pe-${storageAccountName}'
  scope: peRg
  params: {
    location: location
    peName: peName
    privateDnsZoneId: privateDnsZoneId
    privateEndpointSubnetId: privateEndpointSubnetId
    privateLinkServiceId: storageAccount.id
    connectionGroupIds: [
      'blob'
    ]
    tags: tags
  }
}

output customDnsConfigs array = privateEndpoint ? pe.outputs.peCustomDnsConfigs : []
output nicIds array = privateEndpoint ? pe.outputs.nicIds : []

output storageAccountName string = storageAccount.name
