$timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }

Start-Transcript -Path "C:\Scripts\Logs\sched_Job_$timestamp.log"

# Get the current date
$today = Get-Date

# Get all Veeam for Microsoft 365 backup jobs that are yearly or monthly
$jobs = Get-VBOJob | Where-Object { $_.Name -like "*Yearly*" -or $_.Name -like "*Monthly*" }

# Loop through each job
foreach ($job in $jobs) {
    # Get the last run time of the job
    $lastRun = Get-VBOJobSession -Job $job | Sort-Object EndTime -Descending | Select-Object -First 1
    # If the job hasn't run in the last month, start the job
    if ($job.Name -like "*Yearly*" -and $lastRun.EndTime -lt ($today.AddYears(-1))) {
        Start-VBOJob -Job $job | Out-Null
        Write-Host "STARTED | Job:" $job.Name " | Last run:" $lastRun.EndTime
    } elseif ($job.Name -like "*Monthly*" -and $lastRun.EndTime -lt ($today.AddMonth(-1))) {
        Start-VBOJob -Job $job | Out-Null
        Write-Host "STARTED | Job:" $job.Name " | Last run:" $lastRun.EndTime
    } else {
        Write-Host "SKIPPED | Job:" $job.Name " | Last run:" $lastRun.EndTime
    }
}

Stop-Transcript