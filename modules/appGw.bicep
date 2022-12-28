param location string
param namingStructure string
param uamiId string
param subnetId string

@description('Array of custom objects: { name: "for use in resource names", appSvcName: "", hostName: "URL", requiresCustomProbe: bool }')
param backendAppSvcs array
param appsRgName string

param tags object = {}

// Retrieve existing App Service instances
resource appsRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
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
var httpSettingsName = 'httpSettings443-'
var frontendIpName = 'appGwPublicFrontendIp'
var frontendPortNamePrefix = 'Public'
var backendAddressPoolNamePrefix = 'be-'
var routingRuleNamePrefix = 'rr-'
var httpListenerNamePrefix = 'l-http-'
var healthProbeNamePrefix = 'hp-'
var frontendPorts = [
  80
  443
]

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
    enableHttp2: true
    // TODO: Required for FedRAMP? enableFips: true

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
        name: frontendIpName
        properties: {
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
    frontendPorts: [for port in frontendPorts: {

      name: '${frontendPortNamePrefix}${port}'
      properties: {
        port: port
      }
    }]
    backendAddressPools: [for (appSvc, i) in backendAppSvcs: {
      name: '${backendAddressPoolNamePrefix}${appSvc.name}'
      properties: {
        backendAddresses: [
          {
            fqdn: appSvcsRes[i].properties.enabledHostNames[0]
          }
        ]
      }
    }]
    backendHttpSettingsCollection: [for (appSvc, i) in backendAppSvcs: {
      name: '${httpSettingsName}${appSvc.name}'
      properties: {
        port: 443
        protocol: 'Https'
        pickHostNameFromBackendAddress: true
        probeEnabled: true
        probe: {
          id: resourceId('Microsoft.Network/applicationGateways/probes', appGwName, '${healthProbeNamePrefix}${appSvc.name}')
        }
      }
    }]
    httpListeners: [for (appSvc, i) in backendAppSvcs: {
      name: '${httpListenerNamePrefix}${appSvc.name}'
      properties: {
        frontendIPConfiguration: {
          id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, frontendIpName)
        }
        frontendPort: {
          id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, '${frontendPortNamePrefix}80')
        }
        hostName: appSvc.hostName
        protocol: 'Http'
      }
    }]
    requestRoutingRules: [for (appSvc, i) in backendAppSvcs: {
      name: '${routingRuleNamePrefix}${appSvc.name}'
      properties: {
        ruleType: 'Basic'
        priority: 100 + i
        httpListener: {
          id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, '${httpListenerNamePrefix}${appSvc.name}')
        }
        backendAddressPool: {
          id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, '${backendAddressPoolNamePrefix}${appSvc.name}')
        }
        backendHttpSettings: {
          id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, '${httpSettingsName}${appSvc.name}')
        }
      }
    }]
    probes: [for (appSvc, i) in backendAppSvcs: {
      name: '${healthProbeNamePrefix}${appSvc.name}'
      properties: {
        pickHostNameFromBackendHttpSettings: true
        timeout: 30
        interval: 30
        path: appSvc.customProbePath
        protocol: 'Https'
      }
    }]
  }
  tags: tags
}

output appGwName string = appGwName
