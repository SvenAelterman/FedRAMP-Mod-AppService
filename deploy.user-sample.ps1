# MODIFY HERE
[string]$WorkloadName = 'NAME OF YOUR APPLICATION/WORKLOAD'
[string]$Environment = 'TEST'
[int]$Sequence = 4
[string]$NamingConvention = "{wloadname}-{env}-{rtype}-{loc}-{seq}"

[bool]$DeployDefaultSubnet = $true
[bool]$DeployBastion = $true
[bool]$DeployComputeRg = $true

[string]$TargetSubscription = 'YOUR SUBSCRIPTION NAME OR ID'
[string]$CoreSubscriptionId = 'SUBSCRIPTION ID OF THE HUB SUBSCRIPTION FOR SHARED PRIVATE DNS ZONES'
[string]$CoreDnsZoneResourceGroupName = ' NAME OF THE RESOURCE GROUP IN THE HUB SUBSCRIPTION FOR SHARED PRIVATE DNS ZONES'

[int]$VNetAddressSpaceOctet4Min = 0
[string]$VNetAddressSpace = '10.0.0.{octet4}'
[int]$VNetCidr = 24
[int]$SubnetCidr = 27

# Leave empty string ('') if no AAD auth for PostgreSQL
[string]$DbAadGroupObjectId = 'AAD OBJECT ID OF A GROUP TO ADMINISTER THE POSTGRESQL FLEXIBLE SERVER (OPTIONAL)'
[string]$DbAadGroupName = 'AAD GROUP NAME (OPTIONAL)'

[string]$PostgreSQLVersion = '14'
[string]$DatabaseName = 'NAME OF A DATABASE TO BE CREATED (OPTIONAL)'

[PSCustomObject]$Tags = @{
	'date-created' = (Get-Date -Format 'yyyy-MM-dd')
	purpose        = $Environment
	lifetime       = 'short'
}

[string]$AppContainerImageName = 'NAME AND TAG OF THE WEB APP CONTAINER IMAGE (IN THE CONTAINER REGISTRY)'
[string]$ApiContainerImageName = 'NAME AND TAG OF THE API APP CONTAINER IMAGE'

[string]$ApiHostName = 'FQDN OF THE API APP'
[string]$WebHostName = 'FQDN OF THE WEB APP'

# Only application settings known before deployment time are listed here
# DB_HOST and DB_NAME are added after PostgreSQL deployment
# Secret values are injected in main.bicep (DB_USER, DB_PASS, EMAIL_TOKEN)
[PSCustomObject]$ApiAppSettings = @{
	NODE_ENV                            = 'localhost'
	DB_PORT                             = 5432
	PORT                                = 80
	WEBSITES_ENABLE_APP_SERVICE_STORAGE = $false
	PRIVATE_KEY                         = ''
	CERT                                = ''
	EMAIL_FROM                          = ''
	CURRENT_URL                         = $ApiHostName
}

# Only if environment variables are needed
[PSCustomObject]$WebAppSettings = @{
}

# LATER: Get from Key Vault (not the project's Key Vault)
[securestring]$DbAdminPassword = (ConvertTo-SecureString -Force -AsPlainText 'Abcd1234')
[securestring]$DbAppSvcPassword = (ConvertTo-SecureString -Force -AsPlainText 'Abcd1234')
[securestring]$DbAppSvcLogin = (ConvertTo-SecureString -Force -AsPlainText 'nolab')
[securestring]$EmailToken = (ConvertTo-SecureString -Force -AsPlainText 'Abcd1234')

[string]$DeveloperPrincipalId = ''

### NEW
[string]$AdminPanelContainerImageName = 'NAME AND TAG OF THE ADMIN PANEL APP CONTAINER IMAGE'
[string]$AdminPanelHostName = 'FQDN OF THE ADMIN PANEL APP'
[PSCustomObject]$AdminPanelAppSettings = @{}

#END MODIFY

./deploy.ps1 -Sequence $Sequence -WorkloadName $WorkloadName -Environment $Environment -DeployBastion $DeployBastion `
	-PostgreSQLVersion $PostgreSQLVersion -DbAdminPassword $DbAdminPassword -DbAppSvcPassword $DbAppSvcPassword -DbAppSvcLogin $DbAppSvcLogin `
	-DbAadGroupObjectId $DbAadGroupObjectId -DbAadGroupName $DbAadGroupName -EmailToken $EmailToken `
	-TargetSubscription $TargetSubscription -CoreSubscriptionId $CoreSubscriptionId `
	-CoreDnsZoneResourceGroupName $CoreDnsZoneResourceGroupName -DeployDefaultSubnet $DeployDefaultSubnet `
	-NamingConvention $NamingConvention -DeployComputeRg $DeployComputeRg `
	-VNetAddressSpaceOctet4Min $VNetAddressSpaceOctet4Min -VNetAddressSpace $VNetAddressSpace -VNetCidr $VNetCidr -SubnetCidr $SubnetCidr `
	-ApiContainerImageName $ApiContainerImageName -AppContainerImageName $AppContainerImageName `
	-Verbose -Tags $Tags -ApiAppSettings $ApiAppSettings -WebAppSettings $WebAppSettings `
	-DatabaseName $DatabaseName -ApiHostName $ApiHostName -WebHostName $WebHostName `
	-DeveloperPrincipalId $DeveloperPrincipalId `
	-AdminPanelAppSettings $AdminPanelAppSettings -AdminPanelContainerImageName $AdminPanelContainerImageName -AdminPanelHostName $AdminPanelHostName
