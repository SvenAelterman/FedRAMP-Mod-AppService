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
	[Parameter(Mandatory = $true)]
	[string]$WorkloadName,
	[int]$Sequence = 1,
	[string]$NamingConvention = "{wloadname}-{env}-{rtype}-{loc}-{seq}",
	[Parameter(Mandatory)]
	[string]$TargetSubscription,
	[Parameter(Mandatory)]
	[string]$ContainerRegistryUrl,
	[Parameter(Mandatory)]
	[string]$EncryptionKeyName,
	[string]$EncryptionKeyVersion,
	[Parameter(Mandatory)]
	[string]$KeyVaultUrl,
	[Parameter(Mandatory)]
	[string]$SubnetId,
	[Parameter(Mandatory)]
	[string]$UAMI,
	[Parameter(Mandatory)]
	[string]$ResourceGroupName,
	[Parameter(Mandatory)]
	[string]$ContainerImage,
	[Parameter(Mandatory)]
	[securestring]$EmailToken,
	[Parameter(Mandatory)]
	[securestring]$DatabasePassword,
	[Parameter(Mandatory)]
	[string]$AppGwUrl
)

$TemplateParameters = @{
	# REQUIRED
	location         = $Location
	environment      = $Environment
	workloadName     = $WorkloadName

	crUrl            = $ContainerRegistryUrl
	ciImage          = $ContainerImage
	ciKeyName        = $EncryptionKeyName
	#ciKeyVersion     = $EncryptionKeyVersion
	kvUrl            = $KeyVaultUrl
	subnetId         = $SubnetId
	uamiId           = $UAMI
	databasePassword = $DatabasePassword
	emailToken       = $EmailToken
	appGwUrl         = $AppGwUrl

	# OPTIONAL
	sequence         = $Sequence
	namingConvention = $NamingConvention
	tags             = @{
		'date-created' = (Get-Date -Format 'yyyy-MM-dd')
		purpose        = $Environment
		lifetime       = 'short'
	}
}

Select-AzSubscription $TargetSubscription

$DeploymentResult = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Location $Location -Name "$WorkloadName-$Environment-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)" `
	-TemplateFile ".\main-ci.bicep" -TemplateParameterObject $TemplateParameters

$DeploymentResult

if ($DeploymentResult.ProvisioningState -eq 'Succeeded') {
	Write-Host "🔥 Deployment successful!"
}
