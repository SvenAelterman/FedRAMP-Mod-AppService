# PowerShell script to deploy the main.bicep template with parameter values

#Requires -Modules "Az", "Microsoft.Graph.Applications"
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
	[string]$NamingConvention = "{wloadname}-{env}-{rtype}-{loc}-{seq}",
	[bool]$DeployBastion = $false,
	[string]$PostgreSQLVersion,
	[securestring]$DbAdminPassword,
	[string]$DbAadGroupObjectId,
	[string]$DbAadGroupName,
	[string]$TargetSubscription,
	[string]$CoreSubscriptionId
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
	coreSubscriptionId = $CoreSubscriptionId

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

# The App ID of the PostgreSQL Flexible Server app to enable AAD auth (fixed across all tenants)
$AzurePostgreSQLFlexSrvAppId = '5657e26c-cc92-45d9-bc47-9da6cfdb4ed9'
Connect-MgGraph -Scopes "Application.ReadWrite.All"

$PostgresSP = Get-MgServicePrincipal -Filter "AppId eq '$AzurePostgreSQLFlexSrvAppId'"

if (! $PostgresSP) {
	Write-Warning "Registering Azure Database for PostgreSQL Flexible Server AAD Authentication app"
	New-MgServicePrincipal -AppId $AzurePostgreSQLFlexSrvAppId
}
else {
	Write-Verbose "$($PostgresSP.DisplayName) is already registered."
}

$DeploymentResult = New-AzDeployment -Location $Location -Name "$WorkloadName-$Environment-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)" `
	-TemplateFile ".\main.bicep" -TemplateParameterObject $TemplateParameters

$DeploymentResult

if ($DeploymentResult.ProvisioningState -eq 'Succeeded') {
	Write-Host "🔥 Deployment successful!"
}
