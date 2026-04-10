## Offboard 5GN Customer ONLY.
## There is some stuff hardcoded into this - down the track I'll make it more robust and variable.

$timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
Start-Transcript -Path ".\Logs\Offboard-5GN-Organization_$timestamp.txt" -Force

try {
    #### START SCRIPT SETUP SECTION ####

    # Load WinSCP .NET assembly
    #$assemblyPath = if ($env:WINSCP_PATH) { $env:WINSCP_PATH } elseif (Test-Path "C:\Program Files (x86)\WinSCP") { "C:\Program Files (x86)\WinSCP" } else { $PSScriptRoot }
    #Add-Type -Path (Join-Path $assemblyPath "WinSCPnet.dll")

    # Import Veeam PowerShell module
    Import-Module Veeam.Archiver.PowerShell

    # Grab and generate info relevant for Veeam offboarding
    Write-Host "Gather customer details" -ForegroundColor Yellow
    $custDomain = Read-Host -Prompt "Please enter the customers domain to be offboarded"
    $cwNumber = Read-Host -Prompt "Enter the ConnectWise customer number (Company_RecID column)"
    $cwName = Read-Host -Prompt "Enter the company name as presented in ConnectWise"

    # Setup variables
    if ($custDomain -like "*.onmicrosoft.com") {
        $custDomainOnMicrosoft = $custDomain
    } else {
        $custDomainSplit = $custDomain -split "\."
        $custDomainShort = $custDomainSplit[0]
        $custDomainOnMicrosoft = ($custdomain -replace '[.-]','')+".onmicrosoft.com"
    }
    $VeeamServer = "MDC-VBM01.5gn.com.au"
    $VeeamS3Account = "vm365-$cwNumber@$cwNumber"
    #$VeeamS3Repo = "vm365-$cwNumber@$cwNumber - 5GN Object Storage"
    $VeeamRepoName = @("vm365-$cwNumber@$cwNumber Local Repo for M365 Backups","vm365-$cwNumber@$cwNumber - 5GN Object Storage")

    # Request the S3 Object Storage credentials
    #Write-Host "Gather object storage credentials" -ForegroundColor Yellow
    #$accessKey = $VeeamS3Account
    #$secretKey = Read-Host -prompt "Please enter the password/secret key for the customer account $accesskey in the Object Storage"

    #### END SCRIPT SETUP SECTION ####
<#
    #### START DATA REMOVAL SECTION #####

    # Set up WinSCP session options
    $sessionOptions = New-Object WinSCP.SessionOptions -Property @{
        Protocol = [WinSCP.Protocol]::S3
        HostName = "mdc-veeam-s3.5gn.com.au"
        UserName = $accessKey
        Password = $secretKey
        Timeout = New-Timespan -Seconds 3600
    }
    $sessionOptions.AddRawSettings("S3UrlStyle", "1")
    $sessionOptions.AddRawSettings("Compressiong", "0")

    # Setup WinSCP Session
    $session = New-Object WinSCP.Session

    try {
        # Connect via WinSCP
        $session.Open($sessionOptions)

        # Find bucket (represented as folder) and pull the folder name. Assumes theres only 1 folder
        $bucket = $session.ListDirectory("/")
        $bucketName = $bucket.Files.Name

        #Delete folder
        Write-Host "We will now attempt to delete all data in $bucketName - this may take an extended period of time. `nPlease be patient - script will timeout after 30 minutes." -ForegroundColor Cyan
        Write-Host "If timeout occurs, you will need to re-execute the script." -ForegroundColor Cyan

        $deleteResult = $session.RemoveFiles($bucketName)

        if ($deleteResult.IsSuccess) {
            Write-Host "Successfully deleted $bucketName" -ForegroundColor Cyan
        } else {
            Write-Host "Failed to delete $bucketName." -ForegroundColor Yellow
            Write-Host "If this is your second or subsquent run, this step will fail if theres nothing left to delete..." -ForegroundColor Cyan
            Write-Host "Failures: $($deleteResult.Failures)" -ForegroundColor Cyan
            Pause
        }
    } catch {
        Write-Host "Something went wrong with the WinSCP Module. This may not be catastrophic if you're runnig this for the second time." -ForegroundColor Cyan
        Write-Host $_.ScriptStackTrace
        Write-Host $_.Error
        Pause
    } finally {
        # Disconnect, clean up
        $session.Dispose()
    }

    #### END DATA REMOVAL SECTION #####
#>
    #### START VEEAM REMOVAL SECTION ####
    try {

        try {
            Connect-VBOServer -Server $veeamServer #-ErrorAction SilentlyContinue
        } catch [System.UnauthorizedAccessException] {
            Write-Host "An authentication error occurred connecting, but it's probably fine - just Veeam things" -ForegroundColor Yellow
        }

        if (-not $(Get-VBOOrganization -Name $custDomainOnMicrosoft)) {
            Write-Host "Customer organization not found, please enter the onmicrosoft.com domain for the customer manually" -ForegroundColor Yellow
            $customName = Read-Host "Enter onmicrosoft.com domain"
            $veeamOrg = Get-VBOOrganization -Name $customName
        } else {
            $VeeamOrg = Get-VBOOrganization -Name $custDomainOnMicrosoft
        }

        $VeeamJob = Get-VBOJob -Organization $VeeamOrg
        foreach ($job in $veeamJob) {
            Write-Host "Removing job: $($job.Name)" -ForegroundColor Cyan
            try {
                Stop-VBOJob -Job $job -ErrorAction:Ignore
            } catch {}

            $VeeamDisableJob = Disable-VBOJob -Job $job
            $VeeamDeleteJob = Remove-VBOJob -Job $job -Confirm:$false
        }

        foreach ($repo in $VeeamRepoName) {
            $VeeamRepository = Get-VBORepository -Name $repo
            if ($VeeamRepository) {
                Write-Host "Removing Repository: $($VeeamRepository.Name)" -ForegroundColor Cyan
                Remove-VBORepository -Repository $VeeamRepository -Confirm:$false -Force:$true
            }

            $VeeamObjectStorageRepository = Get-VBOObjectStorageRepository -Name $repo
            if ($VeeamObjectStorageRepository) {
                Write-Host "Removing Object Storage Repository: $($VeeamObjectStorageRepository.Name)" -ForegroundColor Cyan
                Remove-VBOObjectStorageRepository -ObjectStorageRepository $VeeamObjectStorageRepository -Confirm:$false
            }
        }

        $veeamObjectStorageKey = Get-VBOAmazonS3CompatibleAccount -AccessKey $VeeamS3Account
        if ($veeamObjectStorageKey) {
            foreach ($account in $veeamObjectStorageKey) {
                Write-Host "Removing Access Key: $($account.AccessKey)" -ForegroundColor Cyan
                Remove-VBOAmazonS3CompatibleAccount -Account $account -Confirm:$false
            }
        }

        $VeeamEncryptionKey = $null
        while (-not $VeeamEncryptionKey) {
            if ($null -ne $custDomain) {
                $VeeamEncryptionKey = Get-VBOEncryptionKey -Description "*$custDomain*"
            }
            if (-not $VeeamEncryptionKey -and $null -ne $cwNanme) {
                $VeeamEncryptionKey = Get-VBOEncryptionKey -Description "*$cwName*"
            }
            if (-not $VeeamEncryptionKey -and $null -ne $cwNumber) {
                $VeeamEncryptionKey = Get-VBOEncryptionKey -Description "*$cwNumber*"
            }
        }

        if ($VeeamEncryptionKey) {
            foreach ($key in $VeeamEncryptionKey) {
                Write-Host "Removing Encryption Key: $($key.Description)" -ForegroundColor Cyan
                Pause
                Remove-VBOEncryptionKey -EncryptionKey $key -Confirm:$false
            }
        } else {
            Write-Host "Could not find the encryption key- please remove manually from Settings > Manage Passwords" -ForegroundColor Yellow
            Pause
        }

        Write-Host "Removing Organization: $custDomainOnMicrosoft" -ForegroundColor Cyan
        Remove-VBOOrganization -Organization $VeeamOrg -Confirm:$false

    } catch {
        Write-Host "The Veeam deletion process failed. Please review the below error and try again." -ForegroundColor Red
        Write-Host $_.Error -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        Write-Host $_
        Pause
        Disconnect-VBOServer
        Exit 1
    } finally {
        Disconnect-VBOServer
    }

    #### END VEEAM REMOVAL SECTION ####

    Write-Host "Please remove namespace and user from Object Storage now -- make sure to mark to delete all data." -ForegroundColor Yellow
    Pause
    Write-Host "Script completed successfully - crack a beer!" -ForegroundColor Green
    Write-Host ".~~~~.
i====i_
|cccc|_)
|cccc|
'-==-'" -ForegroundColor Green
    Pause
} catch {
    Write-Host "Something went catstrophically wrong. Check the error and try again." -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red

    Pause
    Exit 1
}