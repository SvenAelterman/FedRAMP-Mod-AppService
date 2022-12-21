param containerGroupName string
param location string
param uamiId string
param kvUrl string
param ciKeyName string
param crUrl string
param ciImage string
param subnetId string
param wsName string

@secure()
param emailToken string
@secure()
param databasePassword string

param appUrl string

param tags object = {}

resource log 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: wsName
}

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2022-09-01' = {
  name: containerGroupName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    sku: 'Standard'
    diagnostics: {
      logAnalytics: {
        workspaceId: log.properties.customerId
        workspaceKey: listKeys(log.id, log.apiVersion).primarySharedKey
      }
    }
    #disable-next-line BCP035
    encryptionProperties: {
      keyName: ciKeyName
      vaultBaseUrl: kvUrl
      identity: uamiId
    }
    containers: [
      {
        name: containerGroupName

        properties: {
          image: '${crUrl}/${ciImage}'
          environmentVariables: [
            {
              name: 'NODE_ENV'
              value: ''
            }
            {
              name: 'DB_NAME'
              value: ''
            }
            {
              name: 'DB_USER'
              value: ''
            }
            {
              name: 'DB_HOST'
              value: ''
            }
            {
              name: 'DB_PASS'
              secureValue: databasePassword
            }
            {
              name: 'DB_PORT'
              value: ''
            }
            {
              name: 'PORT'
              value: ''
            }
            {
              name: 'PRIVATE_KEY'
              value: ''
            }
            {
              name: 'CERT'
              value: ''
            }
            {
              name: 'EMAIL_TOKEN'
              secureValue: emailToken
            }
            {
              name: 'EMAIL_FROM'
              value: ''
            }
            {
              name: 'CURRENT_URL'
              value: appUrl
            }
          ]
          ports: [
            {
              port: 80
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: 2
              memoryInGB: 8
            }
          }
        }
      }
    ]
    imageRegistryCredentials: [
      {
        server: crUrl
        identity: uamiId
      }
    ]
    ipAddress: {
      ports: [
        {
          port: 80
          protocol: 'TCP'
        }
      ]
      type: 'Private'
    }
    restartPolicy: 'Always'
    osType: 'Linux'
    subnetIds: [
      {
        id: subnetId
      }
    ]
  }
  tags: tags
}

output ciName string = containerGroup.name
