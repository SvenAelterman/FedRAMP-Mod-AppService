# Common Modules

## appSvcKeyVaultRefs.bicep

> **NOTE**: The assumption is that the Key Vault is in the same resource group as the App Service.

### Usage

```bicep
module keyVaultRefsModule '../common-modules/appSvcKeyVaultRefs.bicep' = {
  name: 'keyVaultRefs'
  params: {
    keyVaultName: 'kv-resource-name'
    secretNames: [
      'secret-1'
      'secret-2'
  }
}
```

Sample output

```bicep
[
  '@Microsoft.KeyVault(VaultName=kv-resource-name;SecretName=secret-1)'
  '@Microsoft.KeyVault(VaultName=kv-resource-name;SecretName=secret-2)'
]
```

## roles.bicep

Pending.
