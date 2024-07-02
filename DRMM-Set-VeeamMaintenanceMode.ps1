## Script to enable or disable maintenance mode on a Veeam Cloud Connect host
## and also to add a custom maintenance message if desired
## Designed for usage with Datto RMM

$timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
Start-Transcript -Path "$env:Temp\DRMM-Set-VeeamMaintenanceMode_$timestamp.txt" -Force

$desired = $env:CloudConnectAction
$current = Get-VBRCloudInfrastructureState
$datetime = Get-Date

function Set-MaintenanceMessage {
    [CmdletBinding()]
    param(
      [string]$MaintenanceMessage = $env:MaintenanceMessage,
      [boolean]$ResetMessage = $false,
      [string]$registryKey = "HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication"
    )

    $currentMessage = Get-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage" -ErrorAction SilentlyContinue
    $oldMessage = Get-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage.old" -ErrorAction SilentlyContinue

    if ($resetMessage -eq $true) {
        try {
            if ($currentMessage) {
                Write-Host "Removing existing message: $($currentMessage.CloudMaintenanceModeMessage)" -ForegroundColor Cyan
                $action = Remove-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage" -ErrorAction SilentlyContinue
            }

            if ($oldMessage) {
                Write-Host "Restoring original message: $($oldMessage.'CloudMaintenanceModeMessage.old')" -ForegroundColor Cyan
                $action = Rename-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage.old" -NewName "CloudMaintenanceModeMessage"
            } else {
                Write-Host "SUCCESS: Message reset to default" -ForegroundColor Green
            }
        } catch {
            Write-Host "FAILED: Error resetting maintenance mode message" -ForegroundColor Red
            Write-Host $_ -ForegroundColor Red
        }
    Return
    }

    if ($MaintenanceMessage) {
        try {
            if ($oldMessage) {
                Write-Host "An old message was found: $($oldMessage.'CloudMaintenanceModeMessage.old')" -ForegroundColor Cyan
                Write-Host "This has been removed, please record this message if required for future reference" -ForegroundColor Cyan
                $action = Remove-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage.old"
            }
            if ($currentMessage) {
                Write-Host "Renaming existing message: $($currentMessage.CloudMaintenanceModeMessage)" -ForegroundColor Cyan
                $action = Rename-ItemProperty -Path $registryKey -Name  "CloudMaintenanceModeMessage" -NewName "CloudMaintenanceModeMessage.old"
            }
            $action = New-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage" -PropertyType String -Value $MaintenanceMessage
        } catch {
            Write-Host "FAILED: Error setting the registry keys to add a custom message" -ForegroundColor Red
            Write-Host $_
            Return
        }

        $newCurrentMessage = Get-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage"
        if ($newCurrentMessage) {
            Write-Host "SUCCESS: Maintenance mode message set in registry" -ForegroundColor Green
            Write-Host $($newCurrentMessage.CloudMaintenanceModeMessage) -ForegroundColor Cyan
        } else {
            Write-Host "WARNING: No maintenance mode message found, so Veeam will display the default message." -ForegroundColor Yellow
        }
        Return
    }

    Write-Host "WARNING: Neither a reset nor a message was passed, but we somehow ended up here..." -ForegroundColor Yellow
}

if ($env:DryRun -eq "true") {
    $whatIf = $true
    Write-Host "We are doing a dry run as selected" -ForegroundColor Yellow
} else {
    $whatIf = $false
}

if ($desired -eq "Maintenance") {
    Write-Host "Enabling maintenance mode on Veeam Cloud Connect server" -ForegroundColor Cyan
    if ($current -eq "Maintenance") {
        Write-Host "WARNING: Maintenance mode already set on server" -ForegroundColor Green
    } else {
        try {
            Enable-VBRCloudMaintenanceMode -Confirm:$False -WhatIf:$whatIf
            if (($whatIf -eq $false) -and ($env:MaintenanceMessage)) {
                Set-MaintenanceMessage
            }
        } catch {
            Write-Host "FAILED: Enabling maintenance mode failed" -ForegroundColor Red
            Write-Host $_
            Exit 1
        }
    }
} else {
    Write-Host "Disabling maintenance mode on Veeam Cloud Connect server"  -ForegroundColor Cyan
    if ($current -eq "Active") {
        Write-Host "WARNING: Maintenance mode already disabled on server" -ForegroundColor Green
    } else {
        try {
            Disable-VBRCloudMaintenanceMode -Confirm:$False -WhatIf:$whatIf
            if ($whatIf -eq $false) {
                Set-MaintenanceMessage -ResetMessage $true
            }
        } catch {
            Write-Host "FAILED: Disabling maintenance mode failed" -ForegroundColor Red
            Write-Host $_
            Exit 1
        }
    }
}

$current = Get-VBRCloudInfrastructureState
#if ($current -eq $desired) {
if (Get-EventLog -LogName "Veeam Backup" -InstanceId 26510 -After $datetime.AddSeconds(-15)) {
    Write-Host "SUCCESS: Successfully set $($env:ComputerName) into $current mode" -ForegroundColor Green
    if ($env:UDF -ne "None") {
        $action = New-ItemProperty -Path "HKLM:\SOFTWARE\CentraStage" -Name Custom$env:UDF -Value $current -Force
    }
} elseif ($current -eq $desired) {
    Write-Host "SUCCESS: The selected $desired mode matches the current $current mode" -ForegroundColor Green
    if ($env:UDF -ne "None") {
        $action = New-ItemProperty -Path "HKLM:\SOFTWARE\CentraStage" -Name Custom$env:UDF -Value $current -Force
    }
} else {
    Write-host "FAILED: $($env:ComputerName) has not correctly gone into $current mode." -ForegroundColor Red
    Exit 1
}
Stop-Transcript