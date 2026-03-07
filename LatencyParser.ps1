param(
    [Parameter(Mandatory = $false)]
    [string]$Path = $PSScriptRoot
)

if (-not (Test-Path -Path $Path)) {
    Write-Host "Error: The specified path '$Path' does not exist." -ForegroundColor Red
    exit 1
}

# Initialize a dictionary to store all percentile data
$allResults = @{}
$fileCount = 0

# Get all text files (skipping CSV files)
$files = Get-ChildItem -Path $path -File | Where-Object { $_.Extension -eq '.txt' }

Write-Host "Found $($files.Count) files to process" -ForegroundColor Cyan

foreach ($file in $files) {
    Write-Host "Processing $($file.Name)..." -NoNewline
    
    try {
        $content = Get-Content -Path $file.FullName -ErrorAction Stop
        
        # Find the start of the latency distribution table
        $startIndex = $content | Select-String -Pattern "Total latency distribution:" -SimpleMatch | 
                        ForEach-Object { $_.LineNumber }
        
        if (-not $startIndex) {
            Write-Host " SKIPPED (No latency table found)" -ForegroundColor Yellow
            continue
        }
        
        # The actual table starts 2 lines after the header
        $tableStartIndex = $startIndex
        
        # Extract table rows until we hit an empty line or end of file
        $tableRows = @()
        $i = $tableStartIndex
        
        while ($i -lt $content.Count) {
            $line = $content[$i]
            if ([string]::IsNullOrWhiteSpace($line)) {
                break
            }
            
            # Skip the header line with column names
            if ($line -match "%-ile \|" -or $line -match "------") {
                $i++
                continue
            }
            
            $tableRows += $line
            $i++
        }
        
        # Process each row of the table
        foreach ($row in $tableRows) {
            # Split the row and clean up whitespace
            $parts = $row -split '\|' | ForEach-Object { $_.Trim() }
            
            if ($parts.Count -ge 4) {
                $percentile = $parts[0]
                $readLatency = [double]($parts[1] -replace ' ms', '')
                $writeLatency = [double]($parts[2] -replace ' ms', '')
                $totalLatency = [double]($parts[3] -replace ' ms', '')
                
                # Initialize the dictionary entry if it doesn't exist
                if (-not $allResults.ContainsKey($percentile)) {
                    $allResults[$percentile] = @{
                        ReadLatencySum = 0
                        WriteLatencySum = 0
                        TotalLatencySum = 0
                        Count = 0
                    }
                }
                
                # Add the values
                $allResults[$percentile].ReadLatencySum += $readLatency
                $allResults[$percentile].WriteLatencySum += $writeLatency
                $allResults[$percentile].TotalLatencySum += $totalLatency
                $allResults[$percentile].Count++
            }
        }
        
        $fileCount++
        Write-Host " SUCCESS" -ForegroundColor Green
    }
    catch {
        Write-Host " ERROR: $_" -ForegroundColor Red
    }
}

if ($fileCount -eq 0) {
    Write-Host "No files were processed successfully. Check your file path and content." -ForegroundColor Red
    exit
}

# Calculate averages and prepare output
$resultsForCsv = @()

# Define the order of percentiles to ensure correct sorting in the output
$percentileOrder = @('min', '25th', '50th', '75th', '90th', '95th', '99th', '3-nines', 
                    '4-nines', '5-nines', '6-nines', '7-nines', '8-nines', '9-nines', 'max')

foreach ($percentile in $percentileOrder) {
    if ($allResults.ContainsKey($percentile)) {
        $entry = $allResults[$percentile]
        
        $resultsForCsv += [PSCustomObject]@{
            Percentile = $percentile
            'Read_Avg_ms' = [math]::Round($entry.ReadLatencySum / $entry.Count, 3)
            'Write_Avg_ms' = [math]::Round($entry.WriteLatencySum / $entry.Count, 3)
            'Total_Avg_ms' = [math]::Round($entry.TotalLatencySum / $entry.Count, 3)
            'SampleCount' = $entry.Count
        }
    }
}

# Export to CSV
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$outputPath = Join-Path -Path $path -ChildPath "latency_averages_$timestamp.csv"
$resultsForCsv | Export-CSV -Path $outputPath -NoTypeInformation


Write-Host "`nProcessing complete. Processed $fileCount files." -ForegroundColor Cyan
Write-Host "Average latency distribution saved to: $outputPath" -ForegroundColor Green
