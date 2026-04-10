$domain = Read-Host -Prompt "What is your login domain"
$username = Read-Host -Prompt "What is your username"
$secPassword = Read-Host -Prompt "What is your password" -AsSecureString
$password =[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPassword))
$vboServer = "MDC-VEEAMP1-MGMT.5gn.com.au"
$certPath = "C:\temp\auth-veeam_2024-25.pfx"
$pfxCert = Get-Content $certPath -Encoding Byte
$b64Cert = [System.Convert]::ToBase64String($pfxCert)
$certThumbprint = "AC000DA6AF138B2C631ED3C06FBCAB049A642378"

#$certPassword = Read-Host "Password" -AsSecureString


$upn = "$domain\$username"
$vboRestAuthBody = "grant_type=password&username=$upn&password=$password&refresh_token=''&client_id=''&assertion=''&integration_token=''"
$vboRestAuth = Invoke-RestMethod -Method Post -Uri "https://MDC-VEEAMP1-mgmt.5gn.com.au:4443/v7/token" -Body $vboRestAuthBody -ContentType "application/x-www-form-urlencoded"
$vboRestAuthExpiry = [DateTime] $vboRestAuth.'.expires'

$vboOrg = Get-VBOOrganization

foreach ($org in $vboOrg) {
    $timeDiff = $vboRestAuthExpiry - $(Get-Date)
    if ($timeDiff.TotalMinutes -lt "5") {
        $vboRestAuthBody = "grant_type=refresh_token&refresh_token=$($vboRestAuth.refresh_token)"
        $vboRestAuth = Invoke-RestMethod -Method Post -Uri "https://$($vboServer):4443/v7/token" -Body $vboRestAuthBody -ContentType "application/x-www-form-urlencoded"
        $vboRestAuthExpiry = [DateTime] $vboRestAuth.'.expires'
    }

    $job = Get-VBOJob -Organization $org
    $repo = Get-VBORepository -Name $Job.Repository
    $users = Get-VBOEntityData -Repository $repo -Type User


    $vboRestURL = "https://$($vboServer):4443/v7/Organizations/$($org.Id)"
    $headers = @{
        "Authorization" = "Bearer $($vboRestAuth.access_token)"
    }

    $vboRestBody = "{
        `"configureApplication`": false,
        `"exchangeOnlineSettings`": {
            `"useApplicationOnlyAuth`": true,
            `"account`": `"$($users[0].Email)`",
            `"grantAdminAccess`": false,
            `"useMfa`": true,
            `"applicationId`": `"$app`",
            `"applicationCertificate`": `"$b64Cert`",
            `"applicationCertificateThumbprint`": `"$certThumbprint`",
            `"applicationCertificatePassword`": `"P@ssw0rd`"
        },
        `"isExchangeOnline`": true,
        `"isSharePointOnline`": false,
        `"isTeamsOnline`": false
    }
    "

    Invoke-RestMethod -Method Put -Uri $vboRestURL -Body $vboRestBody -Headers $headers -ContentType "application/json"
}