param keyVaultName string

param dbAdminPasswordSecretName string
param dbAdminUserNameSecretName string
param craftSecurityKeySecretName string
@secure()
param dbAdminPassword string
@secure()
param dbAdminUserName string
@secure()
param craftSecurityKey string

// @secure()
// param secrets object

resource keyVault 'Microsoft.KeyVault/vaults@2021-11-01-preview' existing = {
  name: keyVaultName
}

resource dbPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  name: dbAdminPasswordSecretName
  parent: keyVault
  properties: {
    contentType: 'MySQL database administrator password'
    value: dbAdminPassword
  }
}

resource dbUserNameSecret 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  name: dbAdminUserNameSecretName
  parent: keyVault
  properties: {
    contentType: 'MySQL database administrator user name'
    value: dbAdminUserName
  }
}

resource craftSecurityKeySecret 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  name: craftSecurityKeySecretName
  parent: keyVault
  properties: {
    contentType: 'Craft CMS instance security key'
    value: craftSecurityKey
  }
}
