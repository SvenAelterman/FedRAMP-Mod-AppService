# PowerShell script to deploy the main.bicep template with parameter values

#Requires -Modules "Az"
#Requires -PSEdition Core

# Use these parameters to customize the deployment instead of modifying the default parameter values
[CmdletBinding()]
Param(
	[ValidateSet('eastus2', 'eastus')]
	[string]$Location = 'eastus',
	# The environment descriptor
	[ValidateSet('test', 'demo', 'prod')]
	[string]$Environment = 'test',
	#
	[Parameter(Mandatory = $true)]
	[string]$WorkloadName,
	#
	[int]$Sequence = 1,
	[string]$NamingConvention = "{rtype}-{wloadname}-{env}-{loc}-{seq}",
	[bool]$DeployBastion = $false,
	[string]$PostgreSQLVersion,
	[securestring]$DbAdminPassword,
	[string]$DbAadGroupObjectId,
	[string]$DbAadGroupName,
	[string]$TargetSubscription
)

$TemplateParameters = @{
	# REQUIRED
	location           = $Location
	environment        = $Environment
	workloadName       = $WorkloadName
	postgresqlVersion  = $PostgreSQLVersion
	dbAdminPassword    = $DbAdminPassword
	dbAadGroupObjectId = $DbAadGroupObjectId
	dbAadGroupName     = $DbAadGroupName

	# OPTIONAL
	deployBastion      = $DeployBastion
	sequence           = $Sequence
	namingConvention   = $NamingConvention
	tags               = @{
		'date-created' = (Get-Date -Format 'yyyy-MM-dd')
		purpose        = $Environment
		lifetime       = 'short'
	}
}

Select-AzSubscription $TargetSubscription

$DeploymentResult = New-AzDeployment -Location $Location -Name "$WorkloadName-$Environment-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)" `
	-TemplateFile ".\main.bicep" -TemplateParameterObject $TemplateParameters

$DeploymentResult

if ($DeploymentResult.ProvisioningState -eq 'Succeeded') {
	Write-Host "🔥 Deployment successful!"
}
