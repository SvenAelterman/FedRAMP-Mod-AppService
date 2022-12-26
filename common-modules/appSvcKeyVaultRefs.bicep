/*
 * This module creates values for App Service or Function App settings that reference a Key Vault secret.
 */

@description('App settings based on Key Vault references. { appSvcSettingName: secretName }')
param appSettingSecretNames object
@description('The name of the Key Vault where the secrets are stored.')
param keyVaultName string

output keyVaultRefs array = [for secret in items(appSettingSecretNames): {
  '${secret.key}': '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=${secret.value})'
}]
