@allowed([
  'eastus2'
  'eastus'
])
param location string
@allowed([
  'test'
  'demo'
  'prod'
])
param environment string
param workloadName string

param crUrl string
param ciImage string
param ciKeyName string
//param ciKeyVersion string
param kvUrl string
param subnetId string
param uamiId string

param tags object = {}
param sequence int = 1
param namingConvention string = '{wloadname}-{env}-{rtype}-{loc}-{seq}'
param deploymentTime string = utcNow()

var sequenceFormatted = format('{0:00}', sequence)
var deploymentNameStructure = '${workloadName}-${environment}-{rtype}-${deploymentTime}'

var thisNamingStructure = replace(replace(replace(namingConvention, '{env}', environment), '{loc}', location), '{seq}', sequenceFormatted)
var namingStructure = replace(thisNamingStructure, '{wloadname}', workloadName)

module cgModule 'modules/ci.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'ci')
  params: {
    location: location
    crUrl: crUrl
    ciImage: ciImage
    ciKeyName: ciKeyName
    //ciKeyVersion: ciKeyVersion
    containerGroupName: replace(namingStructure, '{rtype}', 'ci')
    kvUrl: kvUrl
    subnetId: subnetId
    uamiId: uamiId
    tags: tags
  }
}
