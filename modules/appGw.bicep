param location string
param namingStructure string
param uamiId string
param subnetId string

@description('Array of custom objects: { name: "for use in resource names", appSvcName: "", hostName: "URL" }')
param backendAppSvcs array
param appsRgName string

param tags object = {}

// Retrieve existing App Service instances
resource appsRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  name: appsRgName
  scope: subscription()
}

resource appSvcsRes 'Microsoft.Web/sites@2022-03-01' existing = [for appSvc in backendAppSvcs: {
  name: appSvc.appSvcName
  scope: appsRg
}]

// Create a new public IP address for the App GW frontend
resource pip 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: replace(namingStructure, '{rtype}', 'pip-appgw')
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
  sku: {
    name: 'Standard'
  }
  tags: tags
}

var appGwName = replace(namingStructure, '{rtype}', 'appgw')
var httpSettingsName = 'httpSettings443'

resource appGw 'Microsoft.Network/applicationGateways@2022-05-01' = {
  name: appGwName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    autoscaleConfiguration: {
      minCapacity: 0
      maxCapacity: 10
    }
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Detection'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'Public80'
        properties: {
          port: 80
        }
      }
      {
        name: 'Public443'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [for (appSvc, i) in backendAppSvcs: {
      name: 'be-${appSvc.name}'
      properties: {
        backendAddresses: [
          {
            fqdn: appSvcsRes[i].properties.enabledHostNames[0]
          }
        ]
      }
    }]
    backendHttpSettingsCollection: [
      {
        name: httpSettingsName
        properties: {
          port: 443
          protocol: 'Https'
          pickHostNameFromBackendAddress: true
        }
      }
    ]
    httpListeners: [for (appSvc, i) in backendAppSvcs: {
      name: 'l-http-${appSvc.name}'
      properties: {
        frontendIPConfiguration: {
          id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appGwPublicFrontendIp')
        }
        frontendPort: {
          id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'Public80')
        }
        hostName: appSvc.hostName
        protocol: 'Http'
      }
    }]
    requestRoutingRules: [for (appSvc, i) in backendAppSvcs: {
      name: 'rr-${appSvc.name}'
      properties: {
        ruleType: 'Basic'
        priority: 100 + i
        httpListener: {
          id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'l-http-${appSvc.name}')
        }
        backendAddressPool: {
          id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, 'be-${appSvc.name}')
        }
        backendHttpSettings: {
          id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, httpSettingsName)
        }
      }
    }]
  }
  tags: tags
}

output appGwName string = appGwName
