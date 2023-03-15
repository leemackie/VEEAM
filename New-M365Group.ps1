Add-Type -AssemblyName PresentationCore,PresentationFramework
[System.Windows.MessageBox]::Show('ATTENTION: You will need to utilise a customer global
administrator account for this script to work')

Write-Host "Installing required PowerShell modules"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Find-PackageProvider -Name Nuget -ForceBootstrap -IncludeDependencies -Force | Out-Null

# Determine if ExchangeOnlineManagement module is already present and if so, check for update
if ( -not(Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Install-Module -Name ExchangeOnlineManagement -SkipPublisherCheck -Force -ErrorAction Stop
    Write-Host "ExchangeOnlineManagement module installed successfully" -ForegroundColor Green
}
else {
    Update-Module -Name ExchangeOnlineManagement -ErrorAction Continue
    Write-Host "ExchangeOnlineManagement module already present and up to date" -ForegroundColor Green
}

try {
    do {
        # Collect domain information, and loop until information is correct
        $domain = Read-Host -Prompt "What is the clients 'onmicrosoft' domain name?"
        Write-Host "Domain: $domain" -ForegroundColor Green
        if ((Read-Host -Prompt "Does this look correct? (Y/N)") -eq "N") {
            Write-Host "Start again..." -ForegroundColor Red
            $proceed = $false
        }
        else {
            $proceed = $true
        }
    } until($proceed) { }

    do {
        # Collect group information and loop until information is correct
        $groupName = Read-Host -Prompt "What is the display name of the new group?"
        $groupAlias = Read-Host -Prompt "What is the alias of the new group? (No spaces)"
        $groupDesc = Read-Host -Prompt "What is the description of the group? (Leave blank for no description)"
        $groupOwner = Read-Host -Prompt "Please enter the owner email address"
        Write-Host "Name: $groupName" -ForegroundColor Green
        Write-Host "Alias: $groupAlias" -ForegroundColor Green
        Write-Host "Description: $groupDesc" -ForegroundColor Green
        Write-Host "Owner: $groupOwner" -ForegroundColor Green
        if ((Read-Host -Prompt "Do these look correct? (Y/N)") -eq "N") {
            Write-Host "Start again..." -ForegroundColor Red
            $proceed = $false
        }
        else {
            $proceed = $true
        }
    } until($proceed) { }

    # Connect to Exchange Online as delegated admin
    Connect-ExchangeOnline -DelegatedOrganization $domain

    # Setup new group and then set some properties on the group
    New-UnifiedGroup -DisplayName $groupName -Alias $groupAlias -Notes $groupDesc -AccessType "Private" -Owner $groupOwner
    Set-UnifiedGroup $groupName -UnifiedGroupWelcomeMessageEnabled:$false -HiddenFromAddressListsEnabled $true -HiddenFromExchangeClientsEnabled

}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
}