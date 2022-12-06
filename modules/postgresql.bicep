param location string
param serverName string
param subnetId string
param postgresqlVersion string
param privateDnsZoneId string
@secure()
param dbAdminPassword string
param uamiId string

param customerEncryptionKeyUri string = ''

param aadAdminGroupObjectId string = ''
param aadAdminGroupName string = ''

param tags object = {}

resource flexibleServer 'Microsoft.DBforPostgreSQL/flexibleServers@2022-03-08-preview' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    version: postgresqlVersion
    authConfig: empty(aadAdminGroupObjectId) || empty(aadAdminGroupName) ? null : {
      activeDirectoryAuthEnabled: true
      tenantId: subscription().tenantId
    }
    storage: {
      storageSizeGB: 32
    }
    administratorLogin: 'dbadmin'
    administratorLoginPassword: dbAdminPassword
    network: {
      delegatedSubnetResourceId: subnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
    }
    dataEncryption: empty(customerEncryptionKeyUri) ? null : {
      type: 'AzureKeyVault'
      primaryKeyURI: customerEncryptionKeyUri
      primaryUserAssignedIdentityId: uamiId
    }
  }

  resource aadAdmin 'administrators@2022-03-08-preview' = if (!empty(aadAdminGroupObjectId)) {
    name: empty(aadAdminGroupObjectId) ? 'fake' : aadAdminGroupObjectId
    properties: {
      principalType: 'Group'
      tenantId: subscription().tenantId
      principalName: aadAdminGroupName
    }
  }

  tags: tags
}

// resource aadAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2022-03-08-preview' = if (!empty(aadAdminGroupObjectId) && !empty(aadAdminGroupName)) {
//   name: aadAdminGroupObjectId ?? 'fake'
//   parent: flexibleServer
//   properties: {
//     principalType: 'Group'
//     tenantId: subscription().tenantId
//     principalName: aadAdminGroupName
//   }
// }
