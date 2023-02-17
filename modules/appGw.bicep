param location string
param namingStructure string
param uamiId string
param subnetId string

@description('Array of custom objects: { name: "for use in resource names", appSvcName: "", hostName: "URL", customProbePath: "/path/to/health/endpoint" }')
param backendAppSvcs array
@description('The name of the resource group where the App Services live.')
param appsRgName string

param tags object = {}
@description('Set to true if you want the Application Gateway to redirect HTTP requests to the respective HTTPS listener. Requires tlsConfiguration.')
param createHttpRedirectRoutingRules bool = true
@description('TLS certificate information required to configure HTTPS listeners: { certificateSecretId: string, certificateName: string }')
param tlsConfiguration object = {}

// Retrieve existing App Service instances (ensure they exist)
resource appsRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: appsRgName
  scope: subscription()
}

resource appSvcsRes 'Microsoft.Web/sites@2022-03-01' existing = [for appSvc in backendAppSvcs: {
  name: appSvc.appSvcName
  scope: appsRg
}]

// Create a public IP address for the App GW frontend
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

// region Application Gateway name variables
var appGwName = replace(namingStructure, '{rtype}', 'appgw')
var httpSettingsName = 'httpSettings443-'
var frontendIpName = 'appGwPublicFrontendIp'
var frontendPortNamePrefix = 'Public'
var backendAddressPoolNamePrefix = 'be-'
var routingRuleNamePrefix = 'rr-'
var httpListenerNamePrefix = 'l-http'
var healthProbeNamePrefix = 'hp-'
var redirectNamePrefix = 'redirect-'
// endregion

// Always enable HTTPS and HTTP
// No harm in defining an unused port if TLS is not configured or HTTP-to-HTTPS redirects are not configured
// LATER: But it's nicer if it's not there. Only create 80 and/or 443 if needed.
var frontendPorts = [
  80
  443
]

var configureTls = !empty(tlsConfiguration)

// If HTTP (to HTTPS) redirect rules are needed, double the number of routing rules and listeners
var actualCreateHttpRedirectRoutingRules = configureTls && createHttpRedirectRoutingRules
var multiplier = actualCreateHttpRedirectRoutingRules ? 2 : 1

// Determine which back ends need custom health probes and create an array
var probesArray = [for appSvc in backendAppSvcs: !empty(appSvc.customProbePath) ? {
  name: '${healthProbeNamePrefix}${appSvc.name}'
  properties: {
    pickHostNameFromBackendHttpSettings: true
    timeout: 30
    interval: 30
    path: appSvc.customProbePath
    protocol: 'Https'
  }
} : {}]
var actualProbesArray = filter(probesArray, p => !empty(p))

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

    sslPolicy: {
      policyName: 'AppGwSslPolicy20220101'
      policyType: 'Predefined'
    }

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

    sslCertificates: configureTls ? [
      {
        name: tlsConfiguration.certificateName
        properties: {
          keyVaultSecretId: tlsConfiguration.certificateSecretId
        }
      }
    ] : []

    // Create one backend address pool for each App Service
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

    // Create one backend HTTP setting for each App Service
    // Technically, App Services with the same health probe path could use the same setting, but that's too difficult to determine in a template
    // The backends are Azure App Services, so they always support HTTPS (and should probably only allow HTTPS)
    backendHttpSettingsCollection: [for appSvc in backendAppSvcs: {
      name: '${httpSettingsName}${appSvc.name}'
      // Unfortunately, cannot dynamically add "probe" property (null is not an accepted value), so need to duplicate most of the properties
      properties: !empty(appSvc.customProbePath) ? {
        port: 443
        protocol: 'Https'
        pickHostNameFromBackendAddress: true
        probe: {
          id: resourceId('Microsoft.Network/applicationGateways/probes', appGwName, '${healthProbeNamePrefix}${appSvc.name}')
        }
      } : {
        port: 443
        protocol: 'Https'
        pickHostNameFromBackendAddress: true
      }
    }]
    // Create as many listeners as there are App Services
    // Create additional listeners (multiplier of 2) IF we're deploying TLS with HTTP-to-HTTPS redirects
    httpListeners: [for i in range(0, length(backendAppSvcs) * multiplier): (i < length(backendAppSvcs)) ? {
      // Create HTTPS or HTTP listeners based on the configureTls boolean
      name: '${httpListenerNamePrefix}${configureTls ? 's' : ''}-${backendAppSvcs[i].name}'
      properties: {
        frontendIPConfiguration: {
          id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, frontendIpName)
        }
        frontendPort: {
          id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, '${frontendPortNamePrefix}${configureTls ? '443' : '80'}')
        }
        hostName: backendAppSvcs[i].hostName
        // This is an HTTPS listener if we're configuring TLS; otherwise, HTTP
        protocol: 'Http${configureTls ? 's' : ''}'
        // If we're configuring TLS, this listener needs a reference to the Key Vault TLS certificate
        sslCertificate: configureTls ? {
          id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', appGwName, tlsConfiguration.certificateName)
        } : null
      }
    } : {
      // If we create more listeners than backends, the second set are HTTP listeners to enable redirect
      name: '${httpListenerNamePrefix}-${backendAppSvcs[i - length(backendAppSvcs)].name}'
      properties: {
        frontendIPConfiguration: {
          id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, frontendIpName)
        }
        frontendPort: {
          // Always port 80
          id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, '${frontendPortNamePrefix}80')
        }
        hostName: backendAppSvcs[i - length(backendAppSvcs)].hostName
        // These are always HTTP listeners
        protocol: 'Http'
      }
    }]

    // TODO: Try null instead of {} in the false case; or extract the loop from here like actualProbesArray
    // redirectConfigurations: [for backend in backendAppSvcs: (actualCreateHttpRedirectRoutingRules) ? {
    //   name: '${redirectNamePrefix}${backend.name}'
    //   properties: {
    //     includePath: true
    //     includeQueryString: true
    //     redirectType: 'Permanent'
    //     targetListener: {
    //       id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, '${httpListenerNamePrefix}s-${backend.name}')
    //     }
    //   }
    // } : {}]

    // Create at least one routing rule per App Service
    // Create a second set of routing rules if we're creating HTTP redirects
    requestRoutingRules: [for i in range(0, length(backendAppSvcs) * multiplier): {
      // First length(backendAppSvcs) - 1 iterations create the main routing rules; the second set of iterations create the HTTP redirects if needed
      name: (i < length(backendAppSvcs)) ? '${routingRuleNamePrefix}${backendAppSvcs[i].name}' : '${routingRuleNamePrefix}${backendAppSvcs[i - length(backendAppSvcs)].name}-http-redirect'
      properties: {
        ruleType: 'Basic'
        priority: 100 + i
        httpListener: (i < length(backendAppSvcs)) ? {
          // This could be the HTTPS listener or the HTTP listener
          id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, '${httpListenerNamePrefix}${configureTls ? 's' : ''}-${backendAppSvcs[i].name}')
        } : {
          // This is always going to be the HTTP listener
          id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, '${httpListenerNamePrefix}-${backendAppSvcs[i - length(backendAppSvcs)].name}')
        }
        backendAddressPool: (i < length(backendAppSvcs)) ? {
          id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, '${backendAddressPoolNamePrefix}${backendAppSvcs[i].name}')
        } : null
        backendHttpSettings: (i < length(backendAppSvcs)) ? {
          id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, '${httpSettingsName}${backendAppSvcs[i].name}')
        } : null
        redirectConfiguration: (i >= length(backendAppSvcs)) ? {
          id: resourceId('Microsoft.Network/applicationGateways/redirectConfigurations', appGwName, '${redirectNamePrefix}${backendAppSvcs[i - length(backendAppSvcs)].name}')
        } : null
      }
    }]
    // For each site that needs a custom probe, the probe array contains a health probe configuration
    probes: actualProbesArray
  }
  tags: tags
}

output appGwName string = appGwName
output publicIpAddress string = pip.properties.ipAddress
output tlsConfigured bool = configureTls
