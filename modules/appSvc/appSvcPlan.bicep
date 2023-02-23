param location string
param appSvcPlanName string

param tags object = {}

resource appSvcPlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appSvcPlanName
  location: location
  kind: 'Linux'
  sku: {
    name: 'S1'
    tier: 'Standard'
  }
  properties: {
    targetWorkerCount: 1
    targetWorkerSizeId: 0
    reserved: true
    zoneRedundant: false
  }
  tags: tags
}

output appSvcPlanName string = appSvcPlan.name
output id string = appSvcPlan.id
