### Downloads and extracts DiskSpd if it is not already available.
### After running, diskspd.exe will be available at .\diskspd\diskspd.exe

param(
    [string]$InstallDirectory = "$PSScriptRoot\diskspd"
)

$exePath = Join-Path $InstallDirectory "diskspd.exe"

if (Test-Path $exePath) {
    Write-Host "DiskSpd already installed at $exePath" -ForegroundColor Green
    return
}

$downloadUrl = "https://github.com/microsoft/diskspd/releases/latest/download/DiskSpd.zip"
$zipPath = Join-Path $env:TEMP "DiskSpd.zip"
$extractPath = Join-Path $env:TEMP "DiskSpd_extract"

try {
    Write-Host "Downloading DiskSpd..." -ForegroundColor Cyan
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

    Write-Host "Extracting..." -ForegroundColor Cyan
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    # Find the amd64 binary (most common); fall back to arm64 or any match
    $diskSpdExe = Get-ChildItem -Path $extractPath -Recurse -Filter "diskspd.exe" |
                    Sort-Object { if ($_.DirectoryName -match 'amd64') { 0 } elseif ($_.DirectoryName -match 'arm64') { 1 } else { 2 } } |
                    Select-Object -First 1

    if (-not $diskSpdExe) {
        Write-Host "Error: Could not find diskspd.exe in the downloaded archive." -ForegroundColor Red
        exit 1
    }

    if (!(Test-Path $InstallDirectory)) {
        New-Item -ItemType Directory -Path $InstallDirectory | Out-Null
    }

    Copy-Item -Path $diskSpdExe.FullName -Destination $exePath -Force
    Write-Host "DiskSpd installed to $exePath" -ForegroundColor Green
} finally {
    # Clean up temp files
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
}
