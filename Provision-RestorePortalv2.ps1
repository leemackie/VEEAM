
##### VBR Service Provider Configuration Area
# Modify the variable below to match your Enterprise Application ID
$applicationId = "9ade80ce-e84c-4bce-b5da-65228d16c2b8"
#####

##### M365 Variables Area #####
$AADGroupDisplayName = "5GN M365 Backup Restore Operators"
$AADGroupDisplayNameLegacy = "5GN VEEAM Restore Operators"
$VBOServer = "MDC-VBM01.5gn.com.au"
#####

$timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
Start-Transcript -Path ".\Logs\Provision-RestorePortal_$timestamp.txt" -Force

Import-Module "Veeam.Archiver.PowerShell"

Write-Host "*** CRITICAL INFORMATION - PLEASE READ ***" -ForegroundColor Yellow -BackgroundColor Black
Write-Host "For this script to complete successfully, the following must be in place:" -ForegroundColor Green
Write-Host "1. The Enterprise Application deployed via CIPP Application Template: 5GN M365 Backup Restore Portal" -ForegroundColor Green
Write-Host "2. The AAD Group $AADGroupDisplayName deployed via CIPP Group Template" -ForegroundColor Green
Write-Host "3. The AAD Group $AADGroupDisplayName populated with the correct members (as a minimum - Global Admins)" -ForegroundColor Green
Pause

$CustomerMicrosoftDomain = Read-Host -Prompt "Please enter the customers onmicrosoft.com domain (e.g. contoso.onmicrosoft.com)"

try {
    # Add the required security group to VEEAM Restore Operators settings
    Write-Host "Setting up Restore Operators in Veeam" -ForegroundColor Green
    Connect-VBOServer -Server $VBOServer
    $VboOrg = Get-VBOOrganization -Name $CustomerMicrosoftDomain
    $VboGroup = Get-VBOOrganizationGroup -Organization $VboOrg -DisplayName $AADGroupDisplayName -DataSource Production -Type Security
    # Do a check for the new group first, if it doesn't exist try to find the legacy group - if neither are found, exit the script with an error message
    if (!$VboGroup) {
        Write-Host "Could not find the AAD Group $AADGroupDisplayName in Veeam - trying to find the legacy group $AADGroupDisplayNameLegacy" -ForegroundColor Yellow
        $VboGroup = Get-VBOOrganizationGroup -Organization $VboOrg -DisplayName $AADGroupDisplayNameLegacy -DataSource Production -Type Security
        if (!$VboGroup) {
            Write-Host "Could not find either the new or legacy AAD Group in Veeam - please review and try again." -ForegroundColor Magenta -BackgroundColor Black
            Pause
            Exit 1
        } else {
            Write-Host "Found the legacy group $AADGroupDisplayNameLegacy in Veeam - using this group for Restore Operators role." -ForegroundColor Green
        }
    } else {
        Write-Host "Found the AAD Group $AADGroupDisplayName in Veeam - using this group for Restore Operators role." -ForegroundColor Green
    }

    $VboRestoreOperator = New-VBORbacOperator -Group $VboGroup
    Add-VBORbacRole -Organization $VboOrg -Name "$CustomerMicrosoftDomain Restore Operators" -Operators $VboRestoreOperator -EntireOrganization -Description "Restore operators for entire organisation - $CustomerMicrosoftDomain" | Out-Null

    Write-Host "Script has completed successfully!" -ForegroundColor Green
    Pause
} catch {
    Write-Host "Something failed adding the Restore Operators to Veeam - review the error and try again." -ForegroundColor Magenta -BackgroundColor Black
    Write-Host $_
    Pause
    Exit 1
}

