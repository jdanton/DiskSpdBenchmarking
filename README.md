# DiskSpdScript
This repository has scripts to use DiskSpd to do benchmark testing.

## Scripts

### `diskspdtest.ps1`

Runs DiskSpd benchmarks on one or more drives for a configurable number of iterations and saves the results as text files.

#### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-DiskspdPath` | string | `diskspd.exe` | Path to the diskspd executable. Defaults to `diskspd.exe` (assumes it is on `PATH`). |
| `-OutputDirectory` | string | `<script dir>\results` | Directory where result files will be saved. Created automatically if it does not exist. |
| `-Drives` | string[] | `@("C")` | Array of drive letters to benchmark. |
| `-Iterations` | int | `5` | Number of benchmark iterations to run per drive. |

#### Usage Examples

```powershell
# Run with defaults (benchmarks C drive, saves results next to the script)
.\diskspdtest.ps1

# Specify a custom diskspd path and output directory
.\diskspdtest.ps1 -DiskspdPath "C:\tools\diskspd\amd64\diskspd.exe" -OutputDirectory "C:\temp\results"

# Benchmark multiple drives
.\diskspdtest.ps1 -Drives @("D", "E") -Iterations 3

# Full example
.\diskspdtest.ps1 -DiskspdPath "C:\diskspd\amd64\diskspd.exe" -OutputDirectory "C:\temp" -Drives @("P", "V") -Iterations 5
```

---

### `LatencyParser.ps1`

Parses DiskSpd output text files from a directory, extracts latency distribution tables, and exports a CSV with averaged percentile latencies.

#### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Path` | string | Script directory (`$PSScriptRoot`) | Directory containing the DiskSpd `.txt` output files to parse. The CSV output is also saved here. |

#### Usage Examples

```powershell
# Run with defaults (reads .txt files from the script's directory)
.\LatencyParser.ps1

# Specify a custom directory containing DiskSpd result files
.\LatencyParser.ps1 -Path "C:\temp\results"

# Use a relative path
.\LatencyParser.ps1 -Path ".\results"
```
