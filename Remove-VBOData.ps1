<#
.NAME
    Veeam Backup for Microsoft Office 365 clean up script for a specific repository
.SYNOPSIS
    Removes all data from a specific repository
.DESCRIPTION
    Script to use for removing all data from a specific repository
    Released under the MIT license.
.LINK
    http://www.github.com/nielsengelen
#>

Import-Module "C:\Program Files\Veeam\Backup365\Veeam.Archiver.PowerShell\Veeam.Archiver.PowerShell.psd1"

Connect-VBOServer -Server (Read-Host "Please enter server name")

$repo = Get-VBORepository -Name (Read-Host "Please enter the repository name")
Clear-Host
Write-Host "-------------" -ForegroundColor Red -BackgroundColor White
Write-Host "Removing data from $($repo.Name)" -ForegroundColor Red -BackgroundColor White

# Remove all users
$usersList = Get-VBOEntityData -Type User -Repository $repo
$totalItems= $usersList.Count
$currentItem = 0
$percentComplete = 0

foreach ($user in $usersList) {
	Write-Progress -Activity "Removing $($user.DisplayName) - $($user.Email)" -Status "($CurrentItem/$TotalItems) Complete:" -PercentComplete $percentComplete
    Remove-VBOEntityData -Repository $repo -User $user -Mailbox -ArchiveMailbox -OneDrive -Sites -Confirm:$false
    $CurrentItem++
    $percentComplete = [int](($CurrentItem / $TotalItems) * 100)
}

# Remove all groups
$groupsList = Get-VBOEntityData -Type Group -Repository $repo
$totalItems= $groupsList.Count
$currentItem = 0
$percentComplete = 0

foreach ($group in $groupsList) {
    Write-Progress -Activity "Removing $($group.DisplayName) - $($group.Email)" -Status "($CurrentItem/$TotalItems) Complete:" -PercentComplete $percentComplete
	Remove-VBOEntityData -Repository $repo -Group $group -Mailbox -ArchiveMailbox -OneDrive -Sites -GroupMailbox -GroupSite -Confirm:$false
    $CurrentItem++
    $percentComplete = [int](($CurrentItem / $TotalItems) * 100)
}

# Remove all sites
$sitesList = Get-VBOEntityData -Type Site -Repository $repo
$totalItems= $sitesList.Count
$currentItem = 0
$percentComplete = 0
foreach ($site in $sitesList) {
    Write-Progress -Activity "Removing $($site.Title) - $($site.Url)" -Status "($CurrentItem/$TotalItems) Complete:" -PercentComplete $percentComplete
	Remove-VBOEntityData -Repository $repo -Site $site -Confirm:$false
    $CurrentItem++
    $percentComplete = [int](($CurrentItem / $TotalItems) * 100)
}

Write-Host "Completed removing data from $($repo.Name)" -ForegroundColor Red -BackgroundColor White
Write-Host "-------------" -ForegroundColor Red -BackgroundColor White
Pause