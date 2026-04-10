Import-Module AzureAD
Import-Module PArtnerCenter

try {
    Connect-VBOServer -Server "MDC-VEEAMP1-MGMT.5gn.com.au"
} catch [System.UnauthorizedAccessException] {
    Write-Host "An authentication error occurred connecting, but it's probably fine - just Veeam things" -ForegroundColor Yellow
}
Connect-PartnerCenter

#[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }
$cer = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 #create a new certificate object
$cer.Import("C:\temp\auth-veeam.cer")
$bin = $cer.GetRawCertData()
$base64Value = [System.Convert]::ToBase64String($bin)
$bin = $cer.GetCertHash()
$base64Thumbprint = [System.Convert]::ToBase64String($bin)
$startDate =  [datetime]::Parse($cer.GetEffectiveDateString())
$startDate = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($StartDate, [System.TimeZoneInfo]::Local.Id, 'GMT Standard Time') #(no MORE the Key credential end date is invalid error)
$endDate =  [datetime]::Parse($cer.GetExpirationDateString())
$endDate = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($endDate, [System.TimeZoneInfo]::Local.Id, 'GMT Standard Time') #(no MORE the Key credential end date is invalid error)

$vboOrg = Get-VBOOrganization -ErrorAction Stop
Connect-AzAccount

$failedOrgs = @{}
foreach ($org in $vboOrg) {
    $applicationID = ($org.Office365ExchangeConnectionSettings).ApplicationID
    $pCustomer = $org.OfficeName
    try {
        $tenantID = (Get-PartnerCustomer -Domain $pCustomer).CustomerId
        if ($tenantID) {
            Write-Host "Connecting to $pCustomer - Tenant ID: $tenantID - App ID: $applicationID" -ForegroundColor Yellow
            Set-AzContext -Tenant $tenantID -Force -Scope Process
            try {
                #$objectId = (Get-AzADApplication -Filter "AppId eq '$applicationID'").Id
                #$azApp = Get-AzADApplication -Filter "AppId eq '$applicationID'"
                $azApp = Get-AzADApplication -DisplayNameStartWith "WCG"
                $azAppCreds = Get-AzADAppCredential -ObjectId $azApp.Id
                Write-Host "Located $pCustomer application" -ForegroundColor Green
                foreach ($x in $azAppCreds) {
                    if ($x.EndDateTime -eq $endDate) {
                        Write-Host "Found current certificate" -ForegroundColor Green
                        $AzAppKey = $true
                    } else {
                        Write-host "Removing old credential" -ForegroundColor Yellow
                        Remove-AzADAppCredential -ObjectId $AzApp.Id -KeyId $x.KeyId
                    }
                }
                if ($azAppKey -ne $true) {
                    New-AzADAppCredential -ObjectId $($azApp.Id) -StartDate $startDate -EndDate $endDate -CustomKeyIdentifier $base64Thumbprint -CertValue $base64Value -ErrorAction SilentlyContinue
                    $azAppCreds = Get-AzADAppCredential -ObjectId $azApp.Id
                    if ($azAppCreds.EndDateTime -ne $endDate) {
                        Write-Host "Failed to add app credential for $pCustomer - App ID $applicationID" -ForegroundColor Red
                        $failedOrgs.Add($pCustomer, "Certificate addition failed - possibly due to permissions")
                    }
                    Write-Host "Completed certificate mangaement for $pCustomer" -ForegroundColor Green
                } else {
                    Write-Host "Certificate already present for $pCustomer" -ForegroundColor Cyan
                }
            } catch {
                Write-Host "Failed to add app credential for $pCustomer - App ID $applicationID" -ForegroundColor Red
                $failedOrgs.Add($pCustomer, $_)
            }
            #Pause
        } else {
            Write-Host "Failed to get tenant ID for $pCustomer" -ForegroundColor Red
            $failedOrgs.Add($pCustomer, "Tenant ID not found")
        }
    } catch {
        Write-Host "Failed to add certificate to $pCustomer" -ForegroundColor Red
        $failedOrgs.Add($pCustomer, $_)
    }
    $azAppKey = $null
    #Clear-AzContext -Force
}

Disconnect-PartnerCenter
Disconnect-AzAccount

Write-Host "Certificate failed on following orgs:"
$failedOrgs
Write-Host "Exporting to CSV @ C:\Temp"
$failedOrgs.GetEnumerator() | Select-Object Key, Value | Export-CSV -path c:\temp\failedorgs.csv -NoTypeInformation
Pause