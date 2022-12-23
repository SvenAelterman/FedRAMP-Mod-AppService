param webAppName string
param location string
param subnetId string
param dbFqdn string
param databaseName string
param dockerImageAndTag string
param dbUserNameConfigValue string
param crLoginServer string
@secure()
param dbPasswordConfigValue string
@secure()
param emailTokenConfigValue string
param appSvcPlanId string

param tags object

var linuxFx = 'DOCKER|${crLoginServer}/${dockerImageAndTag}'

resource appSvc 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  identity: {
    // Create a system assigned managed identity to read Key Vault secrets and pull container images
    type: 'SystemAssigned'
  }
  kind: 'app,linux,container'
  properties: {
    serverFarmId: appSvcPlanId
    virtualNetworkSubnetId: subnetId
    httpsOnly: true
    keyVaultReferenceIdentity: 'SystemAssigned'

    siteConfig: {
      http20Enabled: true
      vnetRouteAllEnabled: true
      alwaysOn: true
      linuxFxVersion: linuxFx
      acrUseManagedIdentityCreds: true
      ftpsState: 'FtpsOnly'

      logsDirectorySizeLimit: 35
      httpLoggingEnabled: true

      // LATER: Pull from secret values and regular values arrays?
      appSettings: [
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${crLoginServer}'
        }
        {
          name: 'NODE_ENV'
          value: 'localhost'
        }
        {
          name: 'DB_PORT'
          value: '5432'
        }
        {
          name: 'DB_HOST'
          value: dbFqdn
        }
        {
          name: 'DB_NAME'
          value: databaseName
        }
        {
          name: 'DB_USER'
          value: dbUserNameConfigValue
        }
        {
          name: 'DB_PASS'
          value: dbPasswordConfigValue
        }
        {
          name: 'PORT'
          value: '80'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'PRIVATE_KEY'
          value: '../key.pem'
        }
        {
          name: 'CERT'
          value: '../server.pem'
        }
        {
          name: 'EMAIL_TOKEN'
          value: emailTokenConfigValue
        }
        {
          name: 'EMAIL_FROM'
          value: 'support@reload-app.com'
        }
        {
          name: 'CURRENT_URL'
          value: 'SET ME'
        }
      ]
    }
  }
  tags: tags
}

output appSvcName string = appSvc.name
output principalId string = appSvc.identity.principalId
