param location string
param namingStructure string

param tags object = {}

resource rt 'Microsoft.Network/routeTables@2022-01-01' = {
  name: replace(namingStructure, '{rtype}', 'rt')
  location: location
  properties: {
    disableBgpRoutePropagation: true

    routes: [
      {
        name: 'Internet-Direct'
        properties: {
          nextHopType: 'Internet'
          addressPrefix: '0.0.0.0/0'
        }
      }
    ]
  }
  tags: tags
}

output routeTableId string = rt.id
