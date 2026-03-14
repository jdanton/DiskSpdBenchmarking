### Warning: This script is for educational purposes only. Use at your own risk.
### It is recommended to not do benchmarks on production systems.
### This script will run diskspd on all non-C: fixed drives for the given number of iterations each.
### It will create a file named "iotest.dat" on each drive and save the results in the output directory.
### Make sure to adjust the parameters as needed.

param(
    [string]$DiskspdPath = "diskspd.exe",
    [string]$OutputDirectory = "$PSScriptRoot\results",
    [int]$Iterations = 5
)

# Define variables
$parameters = "-b8K -d60 -o4 -t32 -h -r -w25 -L -Z1G -c200G"

# Dynamically discover all non-C: fixed disk volumes
$drives = Get-Volume | Where-Object {
    $_.DriveType -eq 'Fixed' -and
    $_.DriveLetter -and
    $_.DriveLetter -ne 'C'
} | Select-Object -ExpandProperty DriveLetter | Sort-Object

if ($drives.Count -eq 0) {
    Write-Host "No non-C: fixed drives detected. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "Detected non-C: fixed drives: $($drives -join ', ')" -ForegroundColor Cyan

# Ensure the output directory exists
if (!(Test-Path -Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

# Loop through each drive
foreach ($drive in $drives) {
    # Create a per-drive subdirectory for results
    $driveOutputDir = Join-Path $OutputDirectory $drive
    if (!(Test-Path -Path $driveOutputDir)) {
        New-Item -ItemType Directory -Path $driveOutputDir | Out-Null
    }

    for ($i = 1; $i -le $Iterations; $i++) {
        # Generate timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

        # Construct the output file name
        $outputFile = "$driveOutputDir\DiskSpeedResults_${drive}_Seq${i}_${timestamp}.txt"

        # Construct the command
        $filePath = "${drive}:\iotest.dat"
        $command = "& `"$DiskspdPath`" $parameters $filePath"

        # Run the command and save output to the new file
        Write-Output "Running diskspd on drive $drive (Iteration $i of $Iterations)..."
        Invoke-Expression "$command | Out-File -FilePath $outputFile -Encoding UTF8"
    }
}

Write-Host "`nAll benchmarks complete. Results saved to: $OutputDirectory" -ForegroundColor Green
