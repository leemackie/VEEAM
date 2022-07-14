######## MODIFY BELOW SETTINGS ###########

##### VBR Service Provider Configuration Area  #####
# Modify the variable below to match your Enterprise Application ID
$applicationId = "9ade80ce-e84c-4bce-b5da-65228d16c2b8"

##### M365 Variables Area #####
$M365GroupName = "5GN VEEAM Restore Operators"
$M365GroupDesc = "Group membership enables members to login to the 5G Networks VEEAM for Microsoft 365 restore portal and initiate tenancy wide restores"

######## STOP HERE ###########

Start-Transcript -Path .\VBRRestorePortal_Log.txt -Append

function Connect-AAD {

  [CmdletBinding()]
  param(
  [Parameter(Mandatory = $true)]
  [string]$tenantid
  )

  try {
    Write-Verbose "Connecting to Microsoft Azure account"
    Connect-AzAccount -Tenant $tenantid -ErrorAction Stop | Out-Null
    $script:context = Get-AzContext
    Write-Verbose "Connecting to Azure AD account"
    Connect-AzureAD -TenantId $context.Tenant.TenantId -AccountId $context.Account.Id -ErrorAction Stop | Out-Null
    Write-Host "$($context.Account.Id) is now connected to Microsoft Azure for $($context.Tenant.Id)" -ForegroundColor Green
  }
  catch {
    Write-Error "An issue occurred while logging into Microsoft. Please double-check your credentials and ensure you have sufficient access."
    throw $_
  }
}

function Connect-VB365RestorePortal {
  <#
.SYNOPSIS
	Enables a Microsoft 365 environment to use a Service Provider's Restore Portal.

.DESCRIPTION
  The script logs in to a tenant Microsoft 365 environment and grants the required permissions so the tenant can leverage a service provider's Veeam Backup for Microsoft 365 Restore Portal.
	
.PARAMETER ApplicationId
	Service Provider (Enterprise Application) Application ID. THIS IS PROVIDED BY YOUR SERVICE PROVIDER.

.PARAMETER TenantID
	Microsoft 365 tenant ID

.OUTPUTS
	Connect-VB365RestorePortal returns string output to guide the user

.EXAMPLE
	Connect-VB365RestorePortal -ApplicationId 58a0f8e1-97bd-4804-ba69-bde1db293223 -tenantid 12345678-90123456

	Description
	-----------
	Connects a Microsoft 365 environment to the specified (Enterprise Application) Application ID

.EXAMPLE
	Connect-VB365RestorePortal -ApplicationId 58a0f8e1-97bd-4804-ba69-bde1db293223 -tenantid 12345678-90123456 -Verbose

	Description
	-----------
	Verbose output is supported

.NOTES
	NAME:  Connect-VB365RestorePortal
	VERSION: 1.0
	AUTHOR: Chris Arceneaux
	TWITTER: @chris_arceneaux
	GITHUB: https://github.com/carceneaux

.LINK
  https://helpcenter.veeam.com/docs/vbo365/guide/ssp_configuration.html

.LINK
  https://helpcenter.veeam.com/docs/vbo365/guide/ssp_ad_application_permissions.html

.LINK
  https://docs.microsoft.com/en-us/powershell/module/azuread/new-azureadserviceprincipal

.LINK
  https://f12.hu/2021/01/13/grant-admin-consent-to-an-azuread-application-via-powershell/

.LINK
	https://arsano.ninja/

#>

  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ApplicationId,
    [string]$tenantid,
    [array]$context
  )

  # check if Enterprise Application already exists
  $sp = Get-AzureADServicePrincipal -Filter "AppId eq '$ApplicationId'"
  if ($sp) {
    Write-Host "Enterprise Application ($ApplicationId) already exists" -ForegroundColor Yellow
  }
  else {
    # creating link to Service Provider Enterprise Application
    try {
      Write-Verbose "Creating new Azure AD Service Principal"
      $sp = New-AzureADServicePrincipal -AppId $ApplicationId -ErrorAction Stop
      Write-Host "$($sp.DisplayName) ($($sp.AppId)) has been linked your account" -ForegroundColor Green
    }
    catch {
      Write-Error "An unexpected error occurred while linking the Enterprise Application to your account."
      throw $_
    }
  }

  # granting admin consent
  $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.TenantId, $null, "Never", $null, "74658136-14ec-4630-ad9b-26e160ff0fc6")
  $headers = @{
    'Authorization'          = 'Bearer ' + $token.AccessToken
    'X-Requested-With'       = 'XMLHttpRequest'
    'x-ms-client-request-id' = New-Guid
    'x-ms-correlation-id'    = New-Guid
  }
  $url = "https://main.iam.ad.ext.azure.com/api/RegisteredApplications/$($sp.AppId)/Consent?onBehalfOfAll=true"
  Write-Verbose "Granting admin consent to the newly linked Azure AD Service Principal"

  # loop waiting for change to actually take place
  while ($true) {
    try {
      Invoke-RestMethod -Uri $url -Headers $headers -Method POST -ErrorAction Stop | Out-Null
      break
    }
    catch {
      Write-Host "Waiting to grant admin consent... (this can take up to 15 minutes)" 
      Write-Verbose "Error: $_"
      Start-Sleep -Seconds 5
    }
  }
  Write-Host "$($sp.DisplayName) ($($sp.AppId)) has been granted admin consent" -ForegroundColor Green
  Write-Host "You can now login to the Service Provider's VB365 Restore Portal!" -ForegroundColor Green
  Write-Warning "If you receive an error, wait 15 minutes and attempt login again."

  # logging out of remote sessions
  Write-Verbose "Logging out of Azure AD account"
  Disconnect-AzureAD | Out-Null
  Write-Verbose "Logging out of Microsoft Azure account"
  Disconnect-AzAccount | Out-Null
}

function Add-RestoreOperators {

  <#
.SYNOPSIS
	Creates a Restore Operators security group in Microsoft 365 and adds members based on the passed array parameter

.DESCRIPTION
  This function creates a Restore Operators security group in Microsoft 365, and then adds members based on a passed MSOLAdmin array to the group automatically
	
.PARAMETER M365GroupName
	The name of the group created in Microsoft 365

.PARAMETER M365GroupDesc
	Microsoft 365 group desription

.PARAMETER tenantid
  The tenant ID from Azure AD

.PARAMETER msolAdmins
  Array of users to be added to the new security group

  #>

  [CmdletBinding()]
  param(
  [Parameter(Mandatory = $true)]
  [string]$M365GroupName,
  [string]$M365GroupDesc,
  [string]$tenantid,
  [array]$MSOLAdmins
  )

  # Setup security group for restore operators in M365
  Write-Verbose "Setting up Restore Operators security group"
  New-MsolGroup -DisplayName $M365GroupName -Description $M365GroupDesc -TenantId $tenantid -OutVariable MSOLGroup -ErrorAction Stop
  Write-Host "Created $M365GroupName - Object ID: " $MSOLGroup.ObjectID -ForegroundColor Green
  # Add users to security group based on MSOLAdmins array
  foreach ($admin in $MSOLAdmins) {
      $name = $admin.DisplayName
      $objID = $admin.ObjectID
      Write-Host "Adding $name to $M365GroupName" -ForegroundColor Green
      Add-MsolGroupMember -GroupObjectId $MSOLGroup.ObjectId -TenantId $tenantid -GroupMemberType User -GroupMemberObjectId $objID | Out-Null
  }
}

function Add-VBORestoreOperators {

  [CmdletBinding()]
  param(
  [Parameter(Mandatory = $true)]
  [string]$domain,
  [string]$M365GroupName
  )

  # Add the required security group to VEEAM Restore Operators settings
  $org = Get-VBOOrganization -Name "$domain"
  $group = Get-VBOOrganizationGroup -Organization $org -DisplayName $M365GroupName
  $restoreoperator = New-VBORbacOperator -Group $Group
  Add-VBORbacRole -Organization $org -Name "$domain Restore Operators" -Operators $restoreoperator -EntireOrganization -Description "Restore operators for entire organiastion - $domain" | Out-Null
}

Write-Host "Installing required PowerShell modules"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Find-PackageProvider -Name Nuget -ForceBootstrap -IncludeDependencies -Force | Out-Null

# Determine if Az.Account module is already present
if ( -not(Get-Module -ListAvailable -Name Az.Accounts)){
  Install-Module -Name Az.Accounts -SkipPublisherCheck -Force -ErrorAction Stop
  Write-Host "Az.Accounts module installed successfully" -ForegroundColor Green
} else {
  Write-Host "Az.Accounts module already present" -ForegroundColor Green
}
# Determine if AzureAd module is already present
if ( -not(Get-Module -ListAvailable -Name AzureAd)){
  Install-Module -Name AzureAD -SkipPublisherCheck -Force -ErrorAction Stop
  Write-Host "AzureAD module installed successfully" -ForegroundColor Green
} else {
  Write-Host "AzureAD module already present" -ForegroundColor Green
}

# Confirm that the MSOnline module is already present
if ( -not(Get-Module -ListAvailable -Name MSOnline)){
    Install-Module MSOnline -SkipPublisherCheck -Force -ErrorAction Stop
    Write-Host "MSOnline module installed successfully" -ForegroundColor Green
} else {
    Write-Host "MSOnline module already present" -ForegroundColor Green
}

# Confirm that the VEEAM Archiver module is already present
if ( -not(Get-Module -ListAvailable -Name Veeam.Archiver.PowerShell)){
  Write-Host "You are not running this on the VBO server - addition of the restore operators group will be skipped." -ForegroundColor Yellow
  $VBOPS = $false
} else {
  Write-Host "VEEAM Archiver Powershell module already present" -ForegroundColor Green
}


# Connect to the MS Online service
  try {
    Write-Verbose "Connecting to Microsoft Online account"
    Connect-MsolService -ErrorAction Stop | Out-Null
  }
  catch {
    Write-Error "An issue occurred while logging into Microsoft. Please double-check your credentials and ensure you have sufficient access."
    throw $_
  }

if ((Read-Host -Prompt "Would you like to import a CSV file? (Y/N)") -eq "Y") {
  try {
    do {
      $csvPath = Read-Host -Prompt "Please enter the path and filename of the CSV file"
    } until($null -ne $csvPath) { }
    
    try {
      $csvContents = Import-CSV -Path $csvPath -ErrorAction Stop
      Write-Host "Imported CSV: $csvPath" -ForegroundColor Green
    } catch {
      Write-Host "Failed CSV Import: $_" -ForegroundColor Red
    }
    
    foreach ($domain in $csvContents) {
      # Collect Tenancy Information
      $tenantID = Get-MsolPartnerContract -DomainName $domain.Name | Select-Object -ExpandProperty TenantId
      if ($null -ne $tenantID) {
        Write-Host "Domain: "$domain.Name -ForegroundColor Green
        Write-Host "Tenant ID: "$tenantID -ForegroundColor Green

        # Get a list of the global admins in the environment, by default we are going to add these to the restore operators group 
        $MSOLAdmins = Get-MsolRoleMember -RoleObjectId $(Get-MsolRole -RoleName "Company Administrator").ObjectId -TenantId $tenantID -ErrorAction Stop

        # Begin setup of the restore operators group via the function
        if (Get-MsolGroup -TenantID $tenantid -SearchString $M365GroupName) {
          Write-Host "Group already exists - Proceeding!" -ForegroundColor Green
        } else {
          Write-Host "Creating Restore Operators group in Microsoft 365" -ForegroundColor Green
          Add-RestoreOperators -M365GroupName $M365GroupName -M365GroupDesc $M365GroupDesc -TenantID $tenantID -MSOLAdmins $MSOLAdmins 
        }
        
        Connect-AAD -tenantid $tenantID
        # Begin setup of the restore portal application via the function
        Write-Host "Creating VBR restore portal application in Azure AD" -ForegroundColor Green
        Connect-VB365RestorePortal -ApplicationId $applicationId -Tenantid $tenantID -context $context

        # Begin setup of the restore operators group on the VBR server
        if ($VBOPS -ne $false) {
          Write-Host "Creating restore operators group in VBO" -ForegroundColor Green
          Add-VBORestoreOperators -domain $domain.Name -M365GroupName $M365GroupName
        }
        Write-Host "Completed tenant" -ForegroundColor Green -BackgroundColor White
      } else {
        Write-Host $domain.Name " has not returned a tenant ID." -ForegroundColor Red
      }
    }
  } catch {
    Write-Host "Something went wrong: $_" -ForegroundColor Red
  }

} else {

  # Begin process to collect tenancy information to use with DAP and create security group for restore operators
  try {
    do {
        # Collect tenancy information, and loop until information is correct
        $domain = Read-Host -Prompt "What is the clients 'onmicrosoft' domain name?"
        $tenantid = Get-MsolPartnerContract -DomainName $domain | Select-Object -ExpandProperty TenantId
        Write-Host "Domain: $domain" -ForegroundColor Green
        Write-Host "Tenant ID: $tenantid" -ForegroundColor Green
        if ((Read-Host -Prompt "Do these look correct? (Y/N)") -eq "N") {
            Write-Host "Start again..." -ForegroundColor Red
            $proceed = $false
        } else {
            $proceed = $true
        }
      } until($proceed) { }

      Connect-AAD -tenantid $tenantid

      # Get a list of the global admins in the environment, we are going to add these to the restore operators group 
      $MSOLAdmins = Get-MsolRoleMember -RoleObjectId $(Get-MsolRole -RoleName "Company Administrator").ObjectId -TenantId $tenantid -ErrorAction Stop
    
      # Begin setup of the restore operators group
      if (-not(Get-MsolGroup -TenantID $tenantid -SearchString $M365GroupName)) {
        Write-Host "Creating Restore Operators group in Microsoft 365" -ForegroundColor Green
        Add-RestoreOperators -M365GroupName $M365GroupName -M365GroupDesc $M365GroupDesc -TenantID $tenantID -MSOLAdmins $MSOLAdmins 
      } else {
        Write-Host "Group already exists - Proceeding!" -ForegroundColor Green
      }

      # Begin setup of the restore portal application
      Write-Host "Creating VBR restore portal application in Azure AD" -ForegroundColor Green
      Connect-VB365RestorePortal -ApplicationId $applicationId -Tenantid $tenantID -context $context

      # Begin setup of the restore operators group on the VBR server
      if ($VBOPS -ne $false) {
        Write-Host "Creating restore operators group in VBO" -ForegroundColor Green
        Add-VBORestoreOperators -domain $domain -M365GroupName $M365GroupName
      }
  } catch {
    Write-Host "Error: $_" -ForegroundColor Red
  }
}

Write-Host "Process is now complete, if you observed any errors please remove any groups created and start script again." -ForegroundColor Green
Write-Host "Output of this script was logged to VBRRestorePortal_Log.txt in the running directory." -ForegroundColor Gray
Stop-Transcript
Pause