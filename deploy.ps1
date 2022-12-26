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
	[securestring]$DbAppSvcLogin,
	[Parameter(Mandatory = $true)]
	[securestring]$DbAppSvcPassword,
	[Parameter(Mandatory = $true)]
	[securestring]$EmailToken,
	[string]$DbAadGroupObjectId,
	[string]$DbAadGroupName,
	[Parameter(Mandatory = $true)]
	[string]$DatabaseName,
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
	[Parameter(Mandatory = $true)]
	[string]$ApiContainerImageName,
	[Parameter(Mandatory = $true)]
	[string]$AppContainerImageName,
	[Parameter(Mandatory = $true)]
	[string]$WebHostName,
	[Parameter(Mandatory = $true)]
	[string]$ApiHostName,
	[bool]$DeployComputeRg = $false,
	[PSCustomObject]$ApiAppSettings = @{},
	[PSCustomObject]$WebAppSettings = @{}
)

Set-StrictMode -Version 2

[PSCustomObject]$TemplateParameters = @{
	# REQUIRED
	location                     = $Location
	environment                  = $Environment.ToUpperInvariant()
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
	databaseName                 = $DatabaseName
	apiHostName                  = $ApiHostName
	webHostName                  = $WebHostName

	# OPTIONAL
	deployBastion                = $DeployBastion
	deployDefaultSubnet          = $DeployDefaultSubnet
	deployComputeRg              = $DeployComputeRg
	apiAppSettings               = $ApiAppSettings
	webAppSettings               = $WebAppSettings
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

	# Enable Container webhooks
	Write-Verbose "Enabling Container Registry Webhooks for Continuous Deployment to App Service"
	# LATER: Do this on a deployment slot instead of the production slot
	az account set --subscription (Get-AzContext).Subscription.Id

	$ApiAppSvcName = $DeploymentResult.Outputs.apiAppSvcName.Value
	$WebAppSvcName = $DeploymentResult.Outputs.webAppSvcName.Value
	$AppsRgName = $DeploymentResult.Outputs.appsRgName.Value
	$CrRgName = $DeploymentResult.Outputs.crResourceGroupName.Value
	$Acr = $DeploymentResult.Outputs.crName.Value

	# Enable CD for API and web containers, output the Webhook URLs
	$ApiCdUrl = az webapp deployment container config --name $ApiAppSvcName --resource-group $AppsRgName --enable-cd true --query CI_CD_URL --output tsv
	$WebCdUrl = az webapp deployment container config --name $WebAppSvcName --resource-group $AppsRgName --enable-cd true --query CI_CD_URL --output tsv

	# Create webhooks in the Container Registry
	$ApiWebHookName = $NamingConvention.Replace('{rtype}', 'wh-api').Replace('{env}', $Environment).Replace('{loc}', $Location).Replace('{seq}', $Sequence).Replace('-', '').Replace('{wloadname}', $WorkloadName)
	$WebWebHookName = $NamingConvention.Replace('{rtype}', 'wh-web').Replace('{env}', $Environment).Replace('{loc}', $Location).Replace('{seq}', $Sequence).Replace('-', '').Replace('{wloadname}', $WorkloadName)
	
	$ApiResult = az acr webhook create --name $ApiWebHookName --registry $Acr --resource-group $CrRgName --actions push --uri $ApiCdUrl --scope $ApiContainerImageName.Substring(0, $ApiContainerImageName.IndexOf(':'))
	$WebResult = az acr webhook create --name $WebWebHookName --registry $Acr --resource-group $CrRgName --actions push --uri $WebCdUrl --scope $AppContainerImageName.Substring(0, $AppContainerImageName.IndexOf(':'))

	Write-Verbose $ApiResult
	Write-Verbose $WebResult

	Write-Warning "`nManual steps: peer the virtual network to the hub`n"

	$KeysSuffix = $DeploymentResult.Outputs.keyVaultKeysUniqueNameSuffix.Value
	Write-Warning "`nBe sure to capture the Key Vault keys' unique suffix: '$KeysSuffix'"
}
