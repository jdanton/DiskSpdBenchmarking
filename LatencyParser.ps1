param(
    [Parameter(Mandatory = $false)]
    [string]$Path = "$PSScriptRoot\results"
)

if (-not (Test-Path -Path $Path)) {
    Write-Host "Error: The specified path '$Path' does not exist." -ForegroundColor Red
    exit 1
}

# --- Helper: Parse latency data from a single DiskSpd output file ---
function Parse-LatencyFile {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath -ErrorAction Stop

    $startIndex = $content | Select-String -Pattern "Total latency distribution:" -SimpleMatch |
                    ForEach-Object { $_.LineNumber }

    if (-not $startIndex) { return $null }

    $tableStartIndex = $startIndex
    $results = @{}
    $i = $tableStartIndex

    while ($i -lt $content.Count) {
        $line = $content[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        if ($line -match "%-ile \|" -or $line -match "------") { $i++; continue }

        $parts = $line -split '\|' | ForEach-Object { $_.Trim() }
        if ($parts.Count -ge 4) {
            $percentile = $parts[0]
            $results[$percentile] = @{
                Read  = [double]($parts[1] -replace ' ms', '')
                Write = [double]($parts[2] -replace ' ms', '')
                Total = [double]($parts[3] -replace ' ms', '')
            }
        }
        $i++
    }

    return $results
}

# --- Helper: Aggregate latency results across multiple files ---
function Get-AggregatedLatency {
    param([string]$Directory)

    $files = Get-ChildItem -Path $Directory -Filter "*.txt" -File
    $allResults = @{}
    $fileCount = 0

    foreach ($file in $files) {
        Write-Host "  Processing $($file.Name)..." -NoNewline
        try {
            $parsed = Parse-LatencyFile -FilePath $file.FullName
            if ($null -eq $parsed) {
                Write-Host " SKIPPED" -ForegroundColor Yellow
                continue
            }
            foreach ($key in $parsed.Keys) {
                if (-not $allResults.ContainsKey($key)) {
                    $allResults[$key] = @{ ReadSum = 0; WriteSum = 0; TotalSum = 0; Count = 0 }
                }
                $allResults[$key].ReadSum  += $parsed[$key].Read
                $allResults[$key].WriteSum += $parsed[$key].Write
                $allResults[$key].TotalSum += $parsed[$key].Total
                $allResults[$key].Count++
            }
            $fileCount++
            Write-Host " OK" -ForegroundColor Green
        } catch {
            Write-Host " ERROR: $_" -ForegroundColor Red
        }
    }

    if ($fileCount -eq 0) { return $null }

    $percentileOrder = @('min','25th','50th','75th','90th','95th','99th',
                         '3-nines','4-nines','5-nines','6-nines','7-nines','8-nines','9-nines','max')

    $rows = @()
    foreach ($p in $percentileOrder) {
        if ($allResults.ContainsKey($p)) {
            $e = $allResults[$p]
            $rows += [PSCustomObject]@{
                Percentile   = $p
                Read_Avg_ms  = [math]::Round($e.ReadSum / $e.Count, 3)
                Write_Avg_ms = [math]::Round($e.WriteSum / $e.Count, 3)
                Total_Avg_ms = [math]::Round($e.TotalSum / $e.Count, 3)
                SampleCount  = $e.Count
            }
        }
    }

    return @{ Rows = $rows; FileCount = $fileCount }
}

# --- SVG Helper: Generate a color for each volume ---
function Get-VolumeColor {
    param([int]$Index)
    $colors = @('#4285F4','#EA4335','#FBBC04','#34A853','#FF6D01','#46BDC6','#7B1FA2','#C2185B')
    return $colors[$Index % $colors.Count]
}

# --- SVG: Bar chart comparing average latency (50th percentile) across volumes ---
function New-BarChartSvg {
    param(
        [hashtable]$VolumeData,  # key = drive letter, value = rows array
        [string]$OutputPath
    )

    $drives = $VolumeData.Keys | Sort-Object
    $barWidth = 60
    $groupGap = 40
    $barGap = 6
    $barsPerGroup = 3  # Read, Write, Total
    $groupWidth = ($barWidth * $barsPerGroup) + ($barGap * ($barsPerGroup - 1)) + $groupGap
    $chartLeft = 80
    $chartTop = 60
    $chartHeight = 320
    $chartWidth = $chartLeft + ($groupWidth * $drives.Count) + 40
    $svgWidth = $chartWidth + 40
    $svgHeight = $chartHeight + $chartTop + 100

    # Collect 50th-percentile values
    $values = @()
    foreach ($d in $drives) {
        $row = $VolumeData[$d] | Where-Object { $_.Percentile -eq '50th' }
        if ($row) { $values += $row.Read_Avg_ms, $row.Write_Avg_ms, $row.Total_Avg_ms }
    }
    if ($values.Count -eq 0) { return }
    $maxVal = ($values | Measure-Object -Maximum).Maximum
    if ($maxVal -eq 0) { $maxVal = 1 }
    $scale = $chartHeight / ($maxVal * 1.2)

    $svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="$svgWidth" height="$svgHeight" viewBox="0 0 $svgWidth $svgHeight">
  <style>
    text { font-family: 'Segoe UI', Arial, sans-serif; }
    .title { font-size: 18px; font-weight: bold; fill: #333; }
    .axis-label { font-size: 16px; fill: #666; }
    .bar-label { font-size: 18px; fill: #333; text-anchor: middle; font-weight: bold; }
    .value-label { font-size: 16px; fill: #333; text-anchor: middle; font-weight: bold; }
    .legend-text { font-size: 12px; fill: #333; }
    .gridline { stroke: #e0e0e0; stroke-width: 1; stroke-dasharray: 4,4; }
  </style>
  <rect width="100%" height="100%" fill="#fafafa" rx="8"/>
  <text x="$(($svgWidth / 2))" y="30" text-anchor="middle" class="title">Median Latency (50th Percentile) by Volume</text>
"@

    # Y-axis gridlines
    $gridLines = 5
    for ($g = 0; $g -le $gridLines; $g++) {
        $yPos = $chartTop + $chartHeight - ($g * $chartHeight / $gridLines)
        $labelVal = [math]::Round(($g * $maxVal * 1.2 / $gridLines), 2)
        $svg += "  <line x1=`"$chartLeft`" y1=`"$yPos`" x2=`"$($chartWidth)`" y2=`"$yPos`" class=`"gridline`"/>`n"
        $svg += "  <text x=`"$($chartLeft - 8)`" y=`"$($yPos + 4)`" text-anchor=`"end`" class=`"axis-label`">$labelVal ms</text>`n"
    }

    # Bars
    $groupIndex = 0
    foreach ($d in $drives) {
        $row = $VolumeData[$d] | Where-Object { $_.Percentile -eq '50th' }
        if (-not $row) { $groupIndex++; continue }

        $groupX = $chartLeft + ($groupIndex * $groupWidth) + ($groupGap / 2)
        $barValues = @($row.Read_Avg_ms, $row.Write_Avg_ms, $row.Total_Avg_ms)
        $barColors = @('#4285F4', '#EA4335', '#34A853')
        $barLabels = @('Read', 'Write', 'Total')

        for ($b = 0; $b -lt $barsPerGroup; $b++) {
            $bx = $groupX + ($b * ($barWidth + $barGap))
            $bh = $barValues[$b] * $scale
            $by = $chartTop + $chartHeight - $bh
            $svg += "  <rect x=`"$bx`" y=`"$by`" width=`"$barWidth`" height=`"$bh`" fill=`"$($barColors[$b])`" rx=`"3`"/>`n"
            $svg += "  <text x=`"$($bx + $barWidth/2)`" y=`"$($by - 5)`" class=`"value-label`">$($barValues[$b]) ms</text>`n"
        }

        # Drive label
        $labelX = $groupX + (($barsPerGroup * ($barWidth + $barGap) - $barGap) / 2)
        $labelY = $chartTop + $chartHeight + 20
        $svg += "  <text x=`"$labelX`" y=`"$labelY`" class=`"bar-label`">Drive $d</text>`n"
        $groupIndex++
    }

    # Legend
    $legendX = $chartLeft
    $legendY = $svgHeight - 30
    $legendItems = @(@('Read','#4285F4'), @('Write','#EA4335'), @('Total','#34A853'))
    $lx = $legendX
    foreach ($item in $legendItems) {
        $svg += "  <rect x=`"$lx`" y=`"$($legendY - 10)`" width=`"14`" height=`"14`" fill=`"$($item[1])`" rx=`"2`"/>`n"
        $svg += "  <text x=`"$($lx + 20)`" y=`"$legendY`" class=`"legend-text`">$($item[0])</text>`n"
        $lx += 80
    }

    $svg += "</svg>"
    $svg | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Bar chart saved to: $OutputPath" -ForegroundColor Green
}

# --- SVG: Tail latency distribution chart (line chart, 90th+ percentiles per volume) ---
function New-DistributionChartSvg {
    param(
        [hashtable]$VolumeData,
        [string]$OutputPath
    )

    $drives = $VolumeData.Keys | Sort-Object
    $tailPercentiles = @('90th','95th','99th','3-nines','4-nines','5-nines','6-nines','7-nines','8-nines','9-nines','max')
    $displayLabels  = @('90th','95th','99th','99.9','99.99','99.999','99.9999','99.99999','99.999999','99.9999999','max')

    $chartLeft = 90
    $chartTop = 60
    $chartWidth = 800
    $chartHeight = 380
    $svgWidth = $chartWidth + $chartLeft + 60
    $svgHeight = $chartHeight + $chartTop + 120

    # Collect all tail latency Total values to find max
    $allVals = @()
    foreach ($d in $drives) {
        foreach ($p in $tailPercentiles) {
            $row = $VolumeData[$d] | Where-Object { $_.Percentile -eq $p }
            if ($row) { $allVals += $row.Total_Avg_ms }
        }
    }
    if ($allVals.Count -eq 0) { return }
    $maxVal = ($allVals | Measure-Object -Maximum).Maximum
    if ($maxVal -eq 0) { $maxVal = 1 }

    $xStep = $chartWidth / [math]::Max(($tailPercentiles.Count - 1), 1)

    $svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="$svgWidth" height="$svgHeight" viewBox="0 0 $svgWidth $svgHeight">
  <style>
    text { font-family: 'Segoe UI', Arial, sans-serif; }
    .title { font-size: 18px; font-weight: bold; fill: #333; }
    .axis-label { font-size: 11px; fill: #666; }
    .legend-text { font-size: 12px; fill: #333; }
    .gridline { stroke: #e0e0e0; stroke-width: 1; stroke-dasharray: 4,4; }
  </style>
  <rect width="100%" height="100%" fill="#fafafa" rx="8"/>
  <text x="$(($svgWidth / 2))" y="30" text-anchor="middle" class="title">Tail Latency Distribution by Volume (Total Avg)</text>
"@

    # Y-axis gridlines
    $gridLines = 6
    for ($g = 0; $g -le $gridLines; $g++) {
        $yPos = $chartTop + $chartHeight - ($g * $chartHeight / $gridLines)
        $labelVal = [math]::Round(($g * $maxVal * 1.15 / $gridLines), 2)
        $svg += "  <line x1=`"$chartLeft`" y1=`"$yPos`" x2=`"$($chartLeft + $chartWidth)`" y2=`"$yPos`" class=`"gridline`"/>`n"
        $svg += "  <text x=`"$($chartLeft - 8)`" y=`"$($yPos + 4)`" text-anchor=`"end`" class=`"axis-label`">$labelVal ms</text>`n"
    }

    # X-axis labels
    for ($xi = 0; $xi -lt $tailPercentiles.Count; $xi++) {
        $xPos = $chartLeft + ($xi * $xStep)
        $svg += "  <text x=`"$xPos`" y=`"$($chartTop + $chartHeight + 20)`" text-anchor=`"middle`" class=`"axis-label`" transform=`"rotate(35 $xPos $($chartTop + $chartHeight + 20))`">$($displayLabels[$xi])</text>`n"
    }

    # Draw lines per volume
    $scale = $chartHeight / ($maxVal * 1.15)
    $driveIndex = 0
    foreach ($d in $drives) {
        $color = Get-VolumeColor -Index $driveIndex
        $points = @()
        foreach ($pi in 0..($tailPercentiles.Count - 1)) {
            $p = $tailPercentiles[$pi]
            $row = $VolumeData[$d] | Where-Object { $_.Percentile -eq $p }
            if ($row) {
                $px = $chartLeft + ($pi * $xStep)
                $py = $chartTop + $chartHeight - ($row.Total_Avg_ms * $scale)
                $points += "$px,$py"
            }
        }

        if ($points.Count -gt 1) {
            $polyline = $points -join ' '
            $svg += "  <polyline points=`"$polyline`" fill=`"none`" stroke=`"$color`" stroke-width=`"2.5`" stroke-linejoin=`"round`"/>`n"
        }

        # Draw dots
        foreach ($pt in $points) {
            $coords = $pt -split ','
            $svg += "  <circle cx=`"$($coords[0])`" cy=`"$($coords[1])`" r=`"4`" fill=`"$color`" stroke=`"#fff`" stroke-width=`"1.5`"/>`n"
        }

        $driveIndex++
    }

    # Legend
    $legendX = $chartLeft
    $legendY = $svgHeight - 30
    $driveIndex = 0
    foreach ($d in $drives) {
        $color = Get-VolumeColor -Index $driveIndex
        $lx = $legendX + ($driveIndex * 100)
        $svg += "  <rect x=`"$lx`" y=`"$($legendY - 10)`" width=`"14`" height=`"14`" fill=`"$color`" rx=`"2`"/>`n"
        $svg += "  <text x=`"$($lx + 20)`" y=`"$legendY`" class=`"legend-text`">Drive $d</text>`n"
        $driveIndex++
    }

    $svg += "</svg>"
    $svg | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Distribution chart saved to: $OutputPath" -ForegroundColor Green
}

# ============================
# Main execution
# ============================

# Discover per-volume subdirectories (each named by drive letter)
$volumeDirs = Get-ChildItem -Path $Path -Directory | Where-Object { $_.Name -match '^[A-Z]$' }

# Fallback: if no per-volume subdirectories, check for .txt files directly (legacy layout)
if ($volumeDirs.Count -eq 0) {
    $txtFiles = Get-ChildItem -Path $Path -Filter "*.txt" -File
    if ($txtFiles.Count -gt 0) {
        Write-Host "No per-volume subdirectories found. Parsing all files in $Path as a single volume..." -ForegroundColor Yellow
        # Try to extract drive letters from filenames like DiskSpeedResults_P_Seq1_...
        $detectedDrives = $txtFiles | ForEach-Object {
            if ($_.Name -match 'DiskSpeedResults_([A-Z])_') { $Matches[1] }
        } | Sort-Object -Unique

        if ($detectedDrives.Count -gt 0) {
            # Group files by drive letter into temp structure
            foreach ($dl in $detectedDrives) {
                $driveDir = Join-Path $Path $dl
                if (!(Test-Path $driveDir)) { New-Item -ItemType Directory -Path $driveDir | Out-Null }
                $txtFiles | Where-Object { $_.Name -match "DiskSpeedResults_${dl}_" } | ForEach-Object {
                    Copy-Item $_.FullName -Destination $driveDir
                }
            }
            $volumeDirs = Get-ChildItem -Path $Path -Directory | Where-Object { $_.Name -match '^[A-Z]$' }
        }
    }
}

if ($volumeDirs.Count -eq 0) {
    Write-Host "No result files found in '$Path'. Ensure benchmark results exist." -ForegroundColor Red
    exit 1
}

Write-Host "Found volumes: $($volumeDirs.Name -join ', ')" -ForegroundColor Cyan

$volumeData = @{}
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

foreach ($dir in $volumeDirs) {
    $driveLetter = $dir.Name
    Write-Host "`nProcessing volume $driveLetter`:" -ForegroundColor Cyan

    $result = Get-AggregatedLatency -Directory $dir.FullName
    if ($null -eq $result) {
        Write-Host "  No valid data for volume $driveLetter" -ForegroundColor Yellow
        continue
    }

    $volumeData[$driveLetter] = $result.Rows

    # Export per-volume CSV
    $csvPath = Join-Path $dir.FullName "latency_averages_${driveLetter}_${timestamp}.csv"
    $result.Rows | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "  CSV saved: $csvPath" -ForegroundColor Green
}

if ($volumeData.Count -eq 0) {
    Write-Host "`nNo valid latency data found across any volume." -ForegroundColor Red
    exit 1
}

# Export combined CSV
$combinedRows = @()
foreach ($d in ($volumeData.Keys | Sort-Object)) {
    foreach ($row in $volumeData[$d]) {
        $combinedRows += [PSCustomObject]@{
            Volume       = $d
            Percentile   = $row.Percentile
            Read_Avg_ms  = $row.Read_Avg_ms
            Write_Avg_ms = $row.Write_Avg_ms
            Total_Avg_ms = $row.Total_Avg_ms
            SampleCount  = $row.SampleCount
        }
    }
}
$combinedCsvPath = Join-Path $Path "latency_combined_${timestamp}.csv"
$combinedRows | Export-Csv -Path $combinedCsvPath -NoTypeInformation
Write-Host "`nCombined CSV saved: $combinedCsvPath" -ForegroundColor Green

# Generate SVG charts
$barChartPath = Join-Path $Path "latency_bar_chart_${timestamp}.svg"
New-BarChartSvg -VolumeData $volumeData -OutputPath $barChartPath

$distChartPath = Join-Path $Path "latency_distribution_${timestamp}.svg"
New-DistributionChartSvg -VolumeData $volumeData -OutputPath $distChartPath

Write-Host "`nAll processing complete." -ForegroundColor Cyan
