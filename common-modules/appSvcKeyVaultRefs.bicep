param secretNames array
param keyVaultName string

output keyVaultRefs array = [for secretName in secretNames: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=${secretName})']
