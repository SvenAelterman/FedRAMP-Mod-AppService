param location string
param namingStructure string
param uamiId string
param subnetId string

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
}

var appGwName = replace(namingStructure, '{rtype}', 'appgw')
var bepName = 'Empty'

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
    backendAddressPools: [
      {
        name: bepName
        properties: {
          backendAddresses: [
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'settings'
        properties: {
          port: 443
          protocol: 'Https'
          pickHostNameFromBackendAddress: false
        }
      }
    ]
    httpListeners: [
      {
        name: 'l-http'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'Public80')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'rr'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'l-http')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, bepName)
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'settings')
          }
        }
      }
    ]
    // probes: [
    //   {
    //     name: 'probe1'
    //     properties: {
    //       pickHostNameFromBackendHttpSettings: true
    //       port: 80
    //       timeout: 30
    //       interval: 30
    //       path: '/'
    //       protocol: 'Http'
    //       backendHttpSettings: [
    //         {
    //           id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'settings')
    //         }
    //       ]
    //     }
    //   }
    // ]
  }
}

output appGwName string = appGwName
