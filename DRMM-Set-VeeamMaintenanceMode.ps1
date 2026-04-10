<#
.SYNOPSIS
Datto RMM script to configure Veeam Cloud Connect server maintenance mode and set a custom message to be displayed to users in maintenance mode if required.

Written by Lee Mackie - 5G Networks

.NOTES
The script is wrapped using pwsh due to the need to run the Veeam PowerShell module in Powershell 7, but it can be easily adapted to run natively in Powershell 5 if required by removing the pwsh wrapper and running the commands directly.

.HISTORY
Version 1.0 - Initial release
Version 1.1 - Updated to wrap in pwsh as per the Note and removed transcript as we output everything we need to the console
#>

$script = @'
    Get-Module -Name Veeam.Backup.PowerShell -ListAvailable | Import-Module -Force -DisableNameChecking

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
                    Write-Host "-- Removing existing message: $($currentMessage.CloudMaintenanceModeMessage)"
                    Remove-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage" -ErrorAction SilentlyContinue | Out-Null
                }

                if ($oldMessage) {
                    Write-Host "-- Restoring original message: $($oldMessage.'CloudMaintenanceModeMessage.old')"
                    Rename-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage.old" -NewName "CloudMaintenanceModeMessage" | Out-Null
                } else {
                    Write-Host "--SUCCESS: Message reset to default"
                }
            } catch {
                Write-Host "!! FAILED: Error resetting maintenance mode message"
                Write-Host $_
                Return
            }
        }

        if ($MaintenanceMessage) {
            try {
                if ($oldMessage) {
                    Write-Host "-- An old message was found: $($oldMessage.'CloudMaintenanceModeMessage.old')"
                    Write-Host "-- This has been removed, please record this message if required for future reference"
                    Remove-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage.old" | Out-Null
                }
                if ($currentMessage) {
                    Write-Host "-- Renaming existing message: $($currentMessage.CloudMaintenanceModeMessage)"
                    Rename-ItemProperty -Path $registryKey -Name  "CloudMaintenanceModeMessage" -NewName "CloudMaintenanceModeMessage.old" | Out-Null
                }
                New-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage" -PropertyType String -Value $MaintenanceMessage | Out-Null
            } catch {
                Write-Host "FAILED: Error setting the registry keys to add a custom message"
                Write-Host $_
                Return
            }

            $newCurrentMessage = Get-ItemProperty -Path $registryKey -Name "CloudMaintenanceModeMessage"
            if ($newCurrentMessage) {
                Write-Host "-- SUCCESS: Maintenance mode message set in registry"
                Write-Host $($newCurrentMessage.CloudMaintenanceModeMessage)
            } else {
                Write-Host "?? WARNING: No maintenance mode message found, so Veeam will display the default message."
            }
        } else {
            Write-Host "-- No custom maintenance message provided, skipping message configuration"
        }
    }

    if ($env:DryRun -eq "true") {
        $whatIf = $true
        Write-Host "-- We are doing a dry run as selected, no changes will be made"
    } else {
        $whatIf = $false
    }

    if ($desired -eq "Maintenance") {
        Write-Host "-- Enabling maintenance mode on Veeam Cloud Connect server"
        if ($current -eq "Maintenance") {
            Write-Host "?? WARNING: Maintenance mode already set on server"
        } else {
            try {
                Enable-VBRCloudMaintenanceMode -Confirm:$False -WhatIf:$whatIf
                if (($whatIf -eq $false) -and ($env:MaintenanceMessage)) {
                    Set-MaintenanceMessage
                }
            } catch {
                Write-Host "!! FAILED: Enabling maintenance mode failed"
                Write-Host $_
                Exit 1
            }
        }
    } else {
        Write-Host "-- Disabling maintenance mode on Veeam Cloud Connect server"
        if ($current -eq "Active") {
            Write-Host "?? WARNING: Maintenance mode already disabled on server"
        } else {
            try {
                Disable-VBRCloudMaintenanceMode -Confirm:$False -WhatIf:$whatIf
                if ($whatIf -eq $false) {
                    Set-MaintenanceMessage -ResetMessage $true
                }
            } catch {
                Write-Host "!! FAILED: Disabling maintenance mode failed"
                Write-Host $_
                Exit 1
            }
        }
    }

    $current = Get-VBRCloudInfrastructureState
    if (Get-EventLog -LogName "Veeam Backup" -InstanceId 26510 -After $datetime.AddSeconds(-15)) {
        Write-Host "-- SUCCESS: Successfully set $($env:ComputerName) into $current mode"
        if ($env:UDF -ne "None") {
            New-ItemProperty -Path "HKLM:\SOFTWARE\CentraStage" -Name Custom$env:UDF -Value $current -Force | Out-Null
        }
    } elseif ($current -eq $desired) {
        Write-Host "-- SUCCESS: The selected $desired mode matches the current $current mode"
        if ($env:UDF -ne "None") {
            New-ItemProperty -Path "HKLM:\SOFTWARE\CentraStage" -Name Custom$env:UDF -Value $current -Force | Out-Null
        }
    } else {
        Write-host "!! FAILED: $($env:ComputerName) has not correctly gone into $current mode."
        Exit 1
    }
'@

# A rather annoying method to determine which version of PowerShell and Veeam module is installed, until Datto RMM supports PowerShell 7 natively
Get-Module -ListAvailable -Name "Veeam.Backup.PowerShell" | ForEach-Object {
    if ($_.Version -lt [version]"13.0" -and $_.Version -ne [version]"0.0") {
        Write-Host "- Veeam PowerShell module version $($_.Version) detected - using standard PowerShell."
        $script | Invoke-Expression
    } elseif ($_.Version -ge [version]"13.0" -or $_.Version -eq [version]"0.0") {
        if (-not $(Get-Command pwsh -ErrorAction SilentlyContinue)) {
            Write-Host "!! ERROR: PowerShell 7 is not installed on this system. This script requires PowerShell 7 to run."
            Exit 1
        }
        Write-Host "- Veeam B&R v13 detected - using PowerShell 7."
        $script | pwsh -Command -

    } else {
        Write-Host "!! ERROR: Veeam PowerShell module not found - please ensure Veeam Backup & Replication is installed on this system."
        Exit 1
    }
}