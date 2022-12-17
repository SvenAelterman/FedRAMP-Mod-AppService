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
          environmentVariables: []
          ports: [
            {
              port: 80
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: 1
              memoryInGB: 2
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
