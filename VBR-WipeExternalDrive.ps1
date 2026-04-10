# Script to wipe the external backup drives, due to the upgrade in backup chain format or for troubleshooting
# Writes a text file to the root of the drive to show that it has been wiped and prevent continuous wiping

# File name to look for
$txtFile = "veeam_wiped.txt"

# Drive letter
$driveLetter = "D"

if ((Test-Path "$($driveLetter):\") -and !(Test-Path "$($driveLetter):\$txtFile")) {
    Write-Host "$driveLetter drive to be wiped"
    $driveLabel = Get-Volume $driveLetter | Select-Object FileSystemLabel
    try {
        ### ReFS on Server
        #Format-Volume -DriveLetter $driveLetter -FileSystem ReFS -AllocationUnitSize 65536 -Force -Verbose
        ### ReFS on Windows 11
        #format "$($driveLetter):" /DevDrv /Q /A:64k
        ### NTFS
        #Format-Volume -DriveLetter $driveLetter -FileSystem NTFS -AllocationUnitSize 65536 -NewFileSystemLabel $driveLabel.FileSystemLabel -Force
    } catch {
        Write-Host "Format failed"
        Write-Host $_
        Exit 1
    }
    New-Item "$($driveLetter):\$txtFile"
}