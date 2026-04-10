Start-Transcript .\Logs\VBO-UpdateauthCertificate.log -Append
Write-Host "Installing required PowerShell modules"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#Find-PackageProvider -Name Nuget -ForceBootstrap -IncludeDependencies -Force | Out-Null

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

Update-AzConfig -EnableLoginByWam $false
Clear-AzConfig -DefaultSubscriptionForLogin

if ( -not(Get-Module -ListAvailable -Name Az.Accounts)){
    Install-Module -Name Az.Accounts -SkipPublisherCheck -Force -ErrorAction Stop -Scope CurrentUser
    Write-Host "Az.Accounts module installed successfully" -ForegroundColor Green

} else {
    Write-Host "Az.Accounts module already present" -ForegroundColor Green
}

if ( -not(Get-Module -ListAvailable -Name Az.Resources)){
    Install-Module -Name Az.Resources -SkipPublisherCheck -Force -ErrorAction Stop -Scope CurrentUser
    Write-Host "Az.Resources module installed successfully" -ForegroundColor Green
} else {
        Write-Host "Az.Resources module already present" -ForegroundColor Green
}

# Determine if AzureAd module is already present
if ( -not(Get-Module -ListAvailable -Name AzureAd)){
Install-Module -Name AzureAD -SkipPublisherCheck -Force -ErrorAction Stop -Scope CurrentUser
Write-Host "AzureAD module installed successfully" -ForegroundColor Green
} else {
Write-Host "AzureAD module already present" -ForegroundColor Green
}

# Confirm that the MSOnline module is already present
if ( -not(Get-Module -ListAvailable -Name MSOnline)){
    Install-Module MSOnline -SkipPublisherCheck -Force -ErrorAction Stop -Scope CurrentUser
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
} catch {
    Write-Error "An issue occurred while logging into Microsoft. Please double-check your credentials and ensure you have sufficient access."
    throw $_
}


#$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate(Read-Host "Please enter the path the certificate file")
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(Read-Host "Please enter the path the certificate file")
$key = [System.Convert]::ToBase64String($cert.GetRawCertData())
$thumbprint = [System.Convert]::ToBase64String($cert.GetCertHash())


$vboServer = Read-Host -Prompt "Please enter the VBO server you would like to connect to"
try {
    Connect-VBOServer -Server $vboServer #-ErrorAction SilentlyContinue
} catch [System.UnauthorizedAccessException] {
    Write-Host "An authentication error occurred connecting, but it's probably fine - just Veeam things" -ForegroundColor Yellow
}

if ((Read-Host -Prompt "Would you like to manually type the organization name? (Y/N)") -eq "N") {
    $vboOrg = Get-VBOOrganization -ErrorAction Stop

    foreach ($domain in $vboOrg) {
    #   $vboApp = $domain | Get-VBOApplication -DisplayName "*veeam*"
        $vboApp = ($domain.Office365ExchangeConnectionSettings).ApplicationID

        # Collect Tenancy Information
        $tenantID = Get-MsolPartnerContract -DomainName $domain.OfficeName | Select-Object -ExpandProperty TenantId
        if ($null -ne $tenantID) {
            Write-Host "Domain: "$domain.OfficeName -ForegroundColor Green
            Write-Host "Tenant ID: "$tenantID -ForegroundColor Green

            Connect-AAD -TenantID $tenantID

            #Write-Host "Adding certificate to application $vboApp" -ForegroundColor Green
            Write-Host "Adding certificate to application $vboApp with thumbprint $thumbprint" -ForegroundColor Green
            New-AzADAppCredential -ApplicationID $vboApp -CertValue $key -CustomKeyIdentifier $thumbprint
            $appCredentials = Get-AzADAppCredential -ApplicationId $vboApp
            $appCredentials | ForEach-Object {
                if ([System.Convert]::ToBase64String($_.CustomKeyIdentifier) -eq $thumbprint) {
                    Write-Host "Success - Added Certificate to AppID $vboApp" -ForegroundColor Green
                    #Break
                }
                #Write-Host "Error - Certificate does not appear to have been added to AppID $vboApp." -ForegroundColor Red
            }

            foreach ($cred in $appCredentials) {
                if ([System.Convert]::ToBase64String($cred.CustomKeyIdentifier) -ne $thumbprint) {
                    Write-Host "Removing old credential - $($cred.DisplayName) - $($cred.StartDateTime)/$($cred.EndDateTime) - $credThumbPrint"
                    Remove-AzADAppCredential -ApplicationID $vboApp -KeyId $cred.KeyId #-WhatIf
                }
            }
        }
    } else {
        $failedorgs += "$domain `n"
    }
} else {
    $org = Read-Host -Prompt "Please enter the name as it appears in Veeam for Microsoft 365 Organization list"
    $vboOrg = Get-VBOOrganization -Name $org -ErrorAction Stop
    $vboApp = ($vboOrg.Office365ExchangeConnectionSettings).ApplicationID

    # Collect Tenancy Information
    $tenantID = Get-MsolPartnerContract -DomainName $vboOrg.OfficeName | Select-Object -ExpandProperty TenantId
    if ($null -ne $tenantID) {
        Write-Host "Domain: "$vboOrg.OfficeName -ForegroundColor Green
        Write-Host "Tenant ID: "$tenantID -ForegroundColor Green

        Connect-AAD -TenantID $tenantID
        Write-Host "Adding certificate to application $vboApp with thumbprint $thumbprint" -ForegroundColor Green
        New-AzADAppCredential -ApplicationID $vboApp -CertValue $key -CustomKeyIdentifier $thumbprint
        $appCredentials = Get-AzADAppCredential -ApplicationId $vboApp
        $appCredentials | ForEach-Object {
            #Write-host "$($_.CustomKeyIdentifier) / $thumbprint"
            if ([System.Convert]::ToBase64String($_.CustomKeyIdentifier) -eq $thumbprint) {
                Write-Host "Success - Added Certificate to AppID $vboApp" -ForegroundColor Green
                Break
            }
            Write-Host "Error - Certificate does not appear to have been added to AppID $vboApp." -ForegroundColor Red
            Pause
            Exit 1
        }

        foreach ($cred in $appCredentials) {
            if ([System.Convert]::ToBase64String($cred.CustomKeyIdentifier) -ne $thumbprint) {
                Write-Host "Removing old credential - $($cred.DisplayName) - $($cred.StartDateTime)/$($cred.EndDateTime) - $credThumbPrint"
                Remove-AzADAppCredential -ApplicationID $vboApp -KeyId $cred.KeyId #-WhatIf
            }
        }
    }
}
Pause