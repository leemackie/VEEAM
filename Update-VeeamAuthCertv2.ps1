$cert = Read-Host "Enter path to auth-veeam certificate"
$certpwd = Read-Host "Enter certificate password" -AsSecureString
$server = Read-Host "Enter Veeam for M365 server"

Connect-VBOServer -Server $server
$vboorg = Get-VBOOrganization

foreach ($org in $vboOrg) {
    $app = Get-VBOApplication -Organization $org -DisplayName 5gnVeeamM365BackupApp
    $newAppSettings = New-VBOOffice365ApplicationOnlyConnectionSettings -ApplicationCertificatePath $cert -ApplicationCertificatePassword $certpwd `
    -ApplicationId $($app.Id)
    Set-VBOOffice365ApplicationOnlyConnectionSettings -Settings $newAppSettings
}