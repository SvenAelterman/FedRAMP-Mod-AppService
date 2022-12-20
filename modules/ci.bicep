param containerGroupName string
param location string
param uamiId string
param kvUrl string
// #disable-next-line no-unused-params
// param ciKeyVersion string
param ciKeyName string
param crUrl string
param ciImage string
param subnetId string

@secure()
param emailToken string
@secure()
param databasePassword string

param appUrl string

param tags object = {}

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
    #disable-next-line BCP035
    encryptionProperties: {
      keyName: ciKeyName
      //keyVersion: ciKeyVersion
      vaultBaseUrl: kvUrl
      identity: uamiId
    }
    containers: [
      {
        name: containerGroupName

        properties: {
          image: '${crUrl}/${ciImage}'
          // TODO: Add here
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
    restartPolicy: 'OnFailure'
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
