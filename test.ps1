[securestring]$EmailToken = (ConvertTo-SecureString -Force -AsPlainText 'Abcd1234')

[hashtable]$AppServices = @{
	"$WorkloadName-Frontend" = @{
		sku  = 'Standard'
		apps = @(
			@{
				Name               = 'web'
				ContainerImageName = 'reload-web:latest'
				HostName           = 'reload.aelterman.cloud'
				AppSettings        = @{
					WEBSITES_PORT = 5002
				}
				SecretAppSettings  = @{}
				RequiresDbSettings = $false
			}
			@{
				Name               = 'admin_panel'
				ContainerImageName = 'admin-panel:latest'
				HostName           = 'reload-admin.aelterman.cloud'
				AppSettings        = @{
					WEBSITES_PORT = 5002
				}
				SecretAppSettings  = @{}
				RequiresDbSettings = $false
			}
		)
	}
	# For backward compatibility
	# This is the API App Service Plan
	"$WorkloadName"          = @{
		sku  = 'Standard'
		apps = @(
			@{
				Name               = 'api'
				ContainerImageName = 'reload-api:latest'
				HostName           = 'reload-api.aelterman.cloud'
				AppSettings        = @{
					NODE_ENV                            = 'localhost'
					DB_PORT                             = 5432
					PORT                                = 80
					WEBSITES_PORT                       = 5002
					WEBSITES_ENABLE_APP_SERVICE_STORAGE = $false
					PRIVATE_KEY                         = '../key.pem'
					CERT                                = '../server.pem'
					EMAIL_FROM                          = 'support@aelterman.cloud'
					CURRENT_URL                         = $ApiHostName
				}
				SecretAppSettings  = @{
					# TODO: Is this retrievable in Bicep? Probably not.
					EMAIL_TOKEN = $EmailToken
				}
				RequiresDbSettings = $true
			}
		)
	}
}

New-AzDeployment -Location eastus -TemplateFile .\test.bicep -appServiceDefinitions $AppServices