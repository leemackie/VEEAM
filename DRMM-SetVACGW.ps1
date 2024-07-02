$veeamURL = $ENV:VeeamURL+":6180:0"

Set-Location -Path HKLM:\Software\Veeam\VAC\Agent
$currentReg = (Get-ItemProperty -Path . -Name CloudGatewayAddress).CloudGatewayAddress

Set-ItemProperty -Path . -Name "CloudGatewayAddress" -Value $null
Set-ItemProperty -Path . -Name "CertificateThumbprint" -Value $null
Set-ItemProperty -Path . -Name "CloudGatewayAddressManual" -Value $VeeamURL

Stop-Service -Name "VeeamManagementAgentSvc" -Force
Start-Service -Name "VeeamManagementAgentSvc"

#Start-Sleep -Seconds 60

$newReg = (Get-ItemProperty -Path . -Name CloudGatewayAddressManual).CloudGatewayAddressManual

Write-Host "Old value: $currentReg"
Write-Host "New value: $newReg"