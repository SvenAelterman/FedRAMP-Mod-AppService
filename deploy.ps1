# PowerShell script to deploy the main.bicep template with parameter values

#Requires -Modules "Az", "Microsoft.Graph.Applications"
#Requires -PSEdition Core

# Use these parameters to customize the deployment instead of modifying the default parameter values
[CmdletBinding()]
Param(
	[ValidateSet('eastus2', 'eastus')]
	[string]$Location = 'eastus',
	[ValidateSet('test', 'demo', 'prod')]
	[string]$Environment = 'test',
	[Parameter(Mandatory = $true)]
	[string]$WorkloadName,
	[int]$Sequence = 1,
	[string]$NamingConvention,
	[bool]$DeployBastion = $false,
	[Parameter(Mandatory = $true)]
	[string]$PostgreSQLVersion,
	[Parameter(Mandatory = $true)]
	[securestring]$DbAdminPassword,
	[Parameter(Mandatory = $true)]
	[string]$DbAppSvcLogin,
	[Parameter(Mandatory = $true)]
	[securestring]$DbAppSvcPassword,
	[Parameter(Mandatory = $true)]
	[securestring]$EmailToken,
	[string]$DbAadGroupObjectId,
	[string]$DbAadGroupName,
	[Parameter(Mandatory = $true)]
	[string]$TargetSubscription,
	[Parameter(Mandatory = $true)]
	[string]$CoreSubscriptionId,
	[Parameter(Mandatory = $true)]
	[string]$CoreDnsZoneResourceGroupName,
	[bool]$DeployDefaultSubnet = $false,
	[Parameter(Mandatory = $true)]
	[int]$VNetAddressSpaceOctet4Min,
	[Parameter(Mandatory = $true)]
	[string]$VNetAddressSpace,
	[Parameter(Mandatory = $true)]
	[int]$VNetCidr,
	[Parameter(Mandatory = $true)]
	[int]$SubnetCidr,
	[PSCustomObject]$Tags = @{},
	[string]$ApiContainerImageName,
	[string]$AppContainerImageName,
	[bool]$DeployComputeRg = $false
)

[PSCustomObject]$TemplateParameters = @{
	# REQUIRED
	location                     = $Location
	environment                  = $Environment
	workloadName                 = $WorkloadName
	postgresqlVersion            = $PostgreSQLVersion
	dbAdminPassword              = $DbAdminPassword
	dbAppSvcPassword             = $DbAppSvcPassword
	emailToken                   = $EmailToken
	dbAppsvcLogin                = $DbAppSvcLogin
	dbAadGroupObjectId           = $DbAadGroupObjectId
	dbAadGroupName               = $DbAadGroupName
	coreSubscriptionId           = $CoreSubscriptionId
	coreDnsZoneResourceGroupName = $CoreDnsZoneResourceGroupName
	vNetAddressSpaceOctet4Min    = $VNetAddressSpaceOctet4Min
	vNetAddressSpace             = $VNetAddressSpace
	vNetCidr                     = $VNetCidr
	subnetCidr                   = $SubnetCidr
	appContainerImageName        = $AppContainerImageName
	apiContainerImageName        = $ApiContainerImageName

	# OPTIONAL
	deployBastion                = $DeployBastion
	deployDefaultSubnet          = $DeployDefaultSubnet
	deployComputeRg              = $DeployComputeRg
	sequence                     = $Sequence
	namingConvention             = $NamingConvention
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

	Write-Verbose "Enabling Static Websites on Azure Storage"
	$PublicStorageAccountName = $DeploymentResult.Outputs.publicStorageAccountName.Value
	$PublicStorageAccountResourceGroupName = $DeploymentResult.Outputs.publicStorageAccountResourceGroupName.Value

	$PublicStorageAccount = Get-AzStorageAccount -ResourceGroupName $PublicStorageAccountResourceGroupName -AccountName $PublicStorageAccountName
	$StorageContext = $PublicStorageAccount.Context

	Enable-AzStorageStaticWebsite -Context $StorageContext

	$KeysSuffix = $DeploymentResult.Outputs.keyVaultKeysUniqueNameSuffix.Value
	Write-Warning "`nBe sure to capture the Key Vault keys' unique suffix: '$KeysSuffix'"
}
