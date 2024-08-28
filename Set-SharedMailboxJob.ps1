$timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
Start-Transcript -Path "C:\Scripts\Logs\SharedMailboxJob\SharedMailbox_sched_Job_$timestamp.log"

# Get all Veeam for Microsoft 365 backup jobs that are yearly or monthly
$jobs = Get-VBOJob | Where-Object { $_.Description -like "*Inclusion Customer" -and $_.Name -like "*Shared Mailbox" }

# Loop through each job
foreach ($job in $jobs) {
    # Get the VBO Organisation for each job we find
    $org = Get-VBOOrganization -Name $job.Organization

    # Enumerate the mailboxes that need to be added by asking Veeam to return Shared Mailboxes that aren't already in the backup job
    $users = Get-VBOOrganizationUser -Organization $org -Type SharedMailbox -NotInJob -DataSource Production

    # Loop through the results adding them to the job
    if ($users) {
        $i = 0
        foreach ($user in $users){
            Write-Host "PROCESSING | Job: $($job.Name) | User: $user"
            Add-VBOBackupItem -Job $job -BackupItem (New-VBOBackupItem -User $user -Mailbox -ArchiveMailbox:$false -OneDrive:$False -Sites:$false) | Out-Null
            $i++
        }
        Write-Host "PROCESSED | Job: $($job.Name) | Mailboxes Added: $i"
    } else {
        Write-Host "SKIPPED | Job: $($job.Name) | No new mailboxes found"
    }
}

# Dance because we're done
Stop-Transcript