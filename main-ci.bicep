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
@secure()
param emailToken string
@secure()
param databasePassword string
param appGwUrl string

param tags object = {}
param sequence int = 1
param namingConvention string = '{wloadname}-{env}-{rtype}-{loc}-{seq}'
param deploymentTime string = utcNow()

//var sequenceFormatted = format('{0:00}', sequence)
var deploymentNameStructure = '${workloadName}-${environment}-{rtype}-${deploymentTime}'

// var thisNamingStructure = replace(replace(replace(namingConvention, '{env}', environment), '{loc}', location), '{seq}', sequenceFormatted)
// var namingStructure = replace(thisNamingStructure, '{wloadname}', workloadName)

// module logModule 'modules/log.bicep' = {
//   name: replace(deploymentNameStructure, '{rtype}', 'log')
//   params: {
//     location: location
//     namingStructure: namingStructure
//     tags: tags
//   }
// }

module ciShortNameModule 'common-modules/shortname.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'ci-name')
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'ci'
    sequence: sequence
    workloadName: workloadName
  }
}

module ciModule 'modules/ci.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'ci')
  params: {
    location: location
    crUrl: crUrl
    ciImage: ciImage
    ciKeyName: ciKeyName
    //ciKeyVersion: ciKeyVersion
    containerGroupName: ciShortNameModule.outputs.shortName
    kvUrl: kvUrl
    subnetId: subnetId
    uamiId: uamiId
    emailToken: emailToken
    databasePassword: databasePassword
    appUrl: appGwUrl
    tags: tags
  }
}
