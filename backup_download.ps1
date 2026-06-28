# ============================================================
# BMAD BACKUP DOWNLOAD SCRIPT - PARALLEL DOWNLOAD
# Download backups from Google Drive to local machine
# ============================================================

param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [string]$Mode = "download",           # download, list, verify
    [string]$BackupDate = "",              # Specific backup date: YYYY-MM, or empty for latest
    [int]$MaxBackups = 0,                  # 0 = all backups
    [switch]$Extract,                      # Extract zips after download
    [switch]$DeleteZipAfterExtract        # Delete zip after successful extraction
)

$ErrorActionPreference = "Continue"

# ===== LOAD CONFIG =====
if (Test-Path $ConfigPath) {
    try {
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        Write-Host "Loaded config from: $ConfigPath" -ForegroundColor Gray
    } catch {
        Write-Host "Failed to load config: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

# ===== EXTRACT CONFIG VALUES =====
$GdriveRemote = $config.paths.gdriveRemote
$GdriveDest = $config.paths.gdriveDest
$downloadDir = if ($config.download.destinationDir) { $config.download.destinationDir } else { "$PSScriptRoot\downloads" }
$batchSize = if ($config.download.batchSize) { $config.download.batchSize } else { 3 }
$maxRetries = if ($config.download.maxRetries) { $config.download.maxRetries } else { 3 }
$verifyAfterDownload = if ($config.download.verifyAfterDownload) { $config.download.verifyAfterDownload } else { $true }

# ===== CONFIGURATION =====
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logfile = "$downloadDir\download_$timestamp.log"

# Create download directory
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

# ===== LOGGING FUNCTION =====
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")

    $logLevels = @("DEBUG", "INFO", "WARNING", "ERROR")
    $currentLevelIdx = $logLevels.IndexOf("INFO")
    $msgLevelIdx = $logLevels.IndexOf($Level)

    if ($msgLevelIdx -lt $currentLevelIdx -and $Level -ne "ERROR") {
        return
    }

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$ts] [$Level] $Message"
    Write-Host $logMsg
    Add-Content -Path $logfile -Value $logMsg
}

# ===== LIST AVAILABLE BACKUPS =====
function Get-AvailableBackups {
    Write-Log "Scanning Google Drive for backups..." "INFO"

    try {
        # List all backup directories
        $result = & rclone lsd "$GdriveRemote`:$GdriveDest" --log-level ERROR 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to list backups" "ERROR"
            return @()
        }

        $backups = @()
        foreach ($line in $result) {
            # Split by whitespace and get the last element (directory name)
            $parts = $line -split '\s+'
            $dirName = $parts[-1]

            # Check if it's a date format (YYYY-MM)
            if ($dirName -match '^\d{4}-\d{2}$') {
                $date = $dirName
                $path = "$GdriveRemote`:$GdriveDest/$date"
                $fileCount = 0

                # Count files in this backup
                $files = & rclone ls "$path" --log-level ERROR 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $fileCount = ($files | Measure-Object).Count
                }

                $backupObj = [PSCustomObject]@{
                    Date = $date
                    Path = $path
                    FileCount = $fileCount
                }
                $backups += $backupObj
                Write-Log "Found backup: $date with $fileCount files" "DEBUG"
            }
        }

        # Sort by date descending
        $backups = $backups | Sort-Object { $_.Date } -Descending

        Write-Log "Found $($backups.Count) backup(s)" "DEBUG"

        return $backups
    } catch {
        Write-Log "Error listing backups: $_" "ERROR"
        return @()
    }
}

# ===== GET FILES IN BACKUP =====
function Get-BackupFiles {
    param([string]$BackupPath)

    try {
        $result = & rclone ls "$BackupPath" --log-level ERROR 2>&1

        $files = @()
        foreach ($line in $result) {
            # Format: "    387 MANIFEST_20260628_111358.txt"
            # Match: size (number) followed by filename
            if ($line -match "^\s*(\d+)\s+(.+)$") {
                $size = [int]$matches[1]
                $fileName = $matches[2]

                $fileObj = [PSCustomObject]@{
                    Name = $fileName
                    Size = $size
                    SizeMB = [math]::Round($size / 1MB, 2)
                    Path = "$BackupPath/$fileName"
                }
                $files += $fileObj
                Write-Log "Found file: $fileName ($([math]::Round($size/1MB,2)) MB)" "DEBUG"
            }
        }

        Write-Log "Total files found: $($files.Count)" "DEBUG"
        return $files
    } catch {
        Write-Log "Error getting files: $_" "ERROR"
        return @()
    }
}

# ===== DOWNLOAD SINGLE FILE =====
function Download-File {
    param([string]$RemotePath, [string]$LocalPath)

    $retry = 0
    $downloadSuccess = $false

    while ($retry -lt $maxRetries -and -not $downloadSuccess) {
        $retry++
        try {
            Write-Log "  Downloading (attempt $retry/$maxRetries): $(Split-Path $RemotePath -Leaf)" "INFO"

            & rclone copyto $RemotePath $LocalPath `
                --progress `
                --log-file $logfile `
                --log-level INFO `
                --retries 3 `
                --low-level-retries 3

            if ($LASTEXITCODE -eq 0 -and (Test-Path $LocalPath)) {
                $localSize = (Get-Item $LocalPath).Length
                Write-Log "  [OK] Downloaded: $([math]::Round($localSize/1MB,2)) MB" "SUCCESS"
                $downloadSuccess = $true
            } else {
                Write-Log "  [FAIL] Download failed (exit: $LASTEXITCODE)" "WARNING"
                Start-Sleep -Seconds 2
            }
        } catch {
            Write-Log "  [FAIL] Download error: $_" "WARNING"
            Start-Sleep -Seconds 2
        }
    }

    return $downloadSuccess
}

# ===== VERIFY DOWNLOADED FILE =====
function Verify-DownloadedFile {
    param([string]$ZipPath)

    if (-not $verifyAfterDownload) {
        return $true
    }

    Write-Log "  Verifying: $(Split-Path $ZipPath -Leaf)" "INFO"

    try {
        # Check if file exists and has content
        if (-not (Test-Path $ZipPath)) {
            Write-Log "  [FAIL] File not found after download" "ERROR"
            return $false
        }

        $file = Get-Item $ZipPath
        if ($file.Length -eq 0) {
            Write-Log "  [FAIL] Downloaded file is empty" "ERROR"
            return $false
        }

        # Try to test zip integrity
        if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
            & 7z.exe t $ZipPath -bso0 -bsp0 > $null 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "  [OK] Zip integrity verified" "SUCCESS"
                return $true
            } else {
                Write-Log "  [!] Zip test failed (may be corrupted)" "WARNING"
                return $false
            }
        } else {
            # PowerShell doesn't have built-in zip test, just check size
            Write-Log "  [OK] File exists and has content" "SUCCESS"
            return $true
        }
    } catch {
        Write-Log "  [FAIL] Verify error: $_" "ERROR"
        return $false
    }
}

# ===== EXTRACT ZIP FILE =====
function Extract-ZipFile {
    param([string]$ZipPath, [string]$DestPath, [bool]$DeleteAfter)

    Write-Log "  Extracting: $(Split-Path $ZipPath -Leaf)" "INFO"

    try {
        # Create destination
        $extractPath = $DestPath
        New-Item -ItemType Directory -Force -Path $extractPath | Out-Null

        # Extract
        if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
            & 7z.exe x $ZipPath "-o$extractPath" -y -bso0 -bsp0 > $null 2>&1
            $exitCode = $LASTEXITCODE
        } else {
            Expand-Archive -Path $ZipPath -DestinationPath $extractPath -Force
            $exitCode = 0
        }

        if ($exitCode -eq 0) {
            Write-Log "  [OK] Extracted to: $extractPath" "SUCCESS"

            # Delete zip if requested
            if ($DeleteAfter) {
                Remove-Item $ZipPath -Force
                Write-Log "  [OK] Deleted zip after extraction" "SUCCESS"
            }

            return $true
        } else {
            Write-Log "  [FAIL] Extraction failed (exit: $exitCode)" "ERROR"
            return $false
        }
    } catch {
        Write-Log "  [FAIL] Extract error: $_" "ERROR"
        return $false
    }
}

# ===== PARALLEL DOWNLOAD FUNCTION =====
function Download-Parallel {
    param([array]$Files, [int]$BatchSize, [string]$DestDir)

    Write-Log "=== PARALLEL DOWNLOAD MODE: Batch size = $BatchSize ===" "INFO"

    $successCount = 0
    $failCount = 0
    $results = @()

    # Process files in batches
    for ($i = 0; $i -lt $Files.Count; $i += $BatchSize) {
        $batch = $Files[$i..[Math]::Min($i + $BatchSize - 1, $Files.Count - 1)]
        Write-Log "Processing batch $([Math]::Floor($i / $BatchSize) + 1): $($batch.Count) files" "INFO"

        # Create runspaces for parallel processing
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $batch.Count)
        $runspacePool.Open()

        $jobs = @()
        foreach ($file in $batch) {
            $powershell = [powershell]::Create()
            $powershell.RunspacePool = $runspacePool

            [void]$powershell.AddScript({
                param($RemotePath, $LocalPath, $maxRetries, $verifyAfterDownload)

                $result = @{
                    Name = Split-Path $RemotePath -Leaf
                    Success = $false
                    Error = ""
                    LocalPath = $LocalPath
                }

                # Download with retry
                $retry = 0
                $downloadSuccess = $false

                while ($retry -lt $maxRetries -and -not $downloadSuccess) {
                    $retry++
                    & rclone copyto $RemotePath $LocalPath --retries 3 --log-level ERROR 2>&1 | Out-Null

                    if ($LASTEXITCODE -eq 0 -and (Test-Path $LocalPath)) {
                        $downloadSuccess = $true
                    } else {
                        Start-Sleep -Seconds 2
                    }
                }

                if ($downloadSuccess) {
                    # Verify
                    if ($verifyAfterDownload) {
                        if ((Get-Item $LocalPath).Length -eq 0) {
                            $result.Error = "Downloaded file is empty"
                        } else {
                            $result.Success = $true
                        }
                    } else {
                        $result.Success = $true
                    }
                } else {
                    $result.Error = "Download failed after $maxRetries attempts"
                }

                return $result
            }).AddParameter("RemotePath", $file.Path).AddParameter("LocalPath", "$DestDir\$($file.Name)").AddParameter("maxRetries", $maxRetries).AddParameter("verifyAfterDownload", $verifyAfterDownload)

            $jobs += @{
                PowerShell = $powershell
                AsyncResult = $powershell.BeginInvoke()
                Result = $null
            }
        }

        # Wait for all jobs in batch to complete
        foreach ($job in $jobs) {
            $job.Result = $job.PowerShell.EndInvoke($job.AsyncResult)
            $job.PowerShell.Dispose()
        }

        $runspacePool.Close()

        # Process results
        foreach ($jobResult in $jobs.Result) {
            $results += $jobResult

            Write-Host "DEBUG: Result for $($jobResult.Name)" -ForegroundColor Cyan
            Write-Host "  Success: $($jobResult.Success)" -ForegroundColor Cyan
            Write-Host "  Error: $($jobResult.Error)" -ForegroundColor Cyan
            Write-Host "  LocalPath: $($jobResult.LocalPath)" -ForegroundColor Cyan
            Write-Host "  File exists: $(Test-Path $jobResult.LocalPath)" -ForegroundColor Cyan

            if ($jobResult.Success) {
                Write-Log "  [OK] $($jobResult.Name)" "SUCCESS"
                Write-Log "  Local: $($jobResult.LocalPath)" "DEBUG"
                $successCount++
            } else {
                Write-Log "  [FAIL] $($jobResult.Name) - $($jobResult.Error)" "ERROR"
                Write-Log "  Local: $($jobResult.LocalPath)" "DEBUG"
                $failCount++
            }
        }

        # Small delay between batches
        if ($i + $BatchSize -lt $Files.Count) {
            Start-Sleep -Seconds 1
        }
    }

    return @{
        Success = $successCount
        Failed = $failCount
        Results = $results
    }
}

# ===== MAIN SCRIPT =====
Write-Log "================================================" "INFO"
Write-Log "BMAD BACKUP DOWNLOAD" "INFO"
Write-Log "Started: $timestamp" "INFO"
Write-Log "Destination: $downloadDir" "INFO"
Write-Log "================================================" "INFO"

# Check rclone
if (-not (Get-Command "rclone" -ErrorAction SilentlyContinue)) {
    Write-Log "[FAIL] rclone not found!" "ERROR"
    exit 1
}

# Check connection
Write-Log "Checking Google Drive connection..." "INFO"
& rclone about "$GdriveRemote`:" --log-level ERROR 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log "[FAIL] Cannot connect to Google Drive" "ERROR"
    exit 1
}
Write-Log "[OK] Connected to Google Drive" "SUCCESS"

# MODE: LIST
if ($Mode -eq "list") {
    Write-Log "=== LISTING AVAILABLE BACKUPS ===" "INFO"

    $backups = Get-AvailableBackups

    Write-Host "`nAvailable Backups:" -ForegroundColor Cyan
    Write-Host "==================" -ForegroundColor Cyan

    if ($backups.Count -eq 0) {
        Write-Host "No backups found" -ForegroundColor Yellow
    } else {
        foreach ($backup in $backups) {
            Write-Host "  [$($backup.Date)] $($backup.FileCount) files" -ForegroundColor White
        }
    }

    Write-Host ""
    exit 0
}

# MODE: DOWNLOAD
if ($Mode -eq "download") {
    # Get available backups
    $backups = Get-AvailableBackups

    if ($backups.Count -eq 0) {
        Write-Log "[FAIL] No backups found on Google Drive" "ERROR"
        exit 1
    }

    # Select backup to download
    $selectedBackup = $null

    if ([string]::IsNullOrWhiteSpace($BackupDate)) {
        # Use latest backup
        $selectedBackup = $backups[0]
        Write-Log "Using latest backup: $($selectedBackup.Date)" "INFO"
    } else {
        # Find specific backup
        $selectedBackup = $backups | Where-Object { $_.Date -eq $BackupDate }
        if (-not $selectedBackup) {
            Write-Log "[FAIL] Backup not found: $BackupDate" "ERROR"
            Write-Log "Available backups: $($backups.Date -join ', ')" "INFO"
            exit 1
        }
        Write-Log "Using backup: $BackupDate" "INFO"
    }

    # Get files in backup
    $files = Get-BackupFiles -BackupPath $selectedBackup.Path

    if ($files.Count -eq 0) {
        Write-Log "[FAIL] No files found in backup" "ERROR"
        exit 1
    }

    Write-Log "Found $($files.Count) files ($([math]::Round(($files | Measure-Object -Property Size -Sum).Sum / 1MB, 2)) MB)" "INFO"

    # Limit files if specified
    if ($MaxBackups -gt 0 -and $files.Count -gt $MaxBackups) {
        $files = $files | Select-Object -First $MaxBackups
        Write-Log "Limited to $MaxBackups files" "INFO"
    }

    # Download files
    $downloadResult = Download-Parallel -Files $files -BatchSize $batchSize -DestDir $downloadDir

    # Summary
    $totalSize = 0
    foreach ($r in $downloadResult.Results) {
        if ($r.Success -and (Test-Path $r.LocalPath)) {
            $totalSize += (Get-Item $r.LocalPath).Length
        }
    }

    Write-Log "================================================" "INFO"
    Write-Log "DOWNLOAD COMPLETED: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "  [OK] Success: $($downloadResult.Success) / $($files.Count)" "INFO"
    Write-Log "  [FAIL] Failed: $($downloadResult.Failed) / $($files.Count)" "INFO"
    Write-Log "  Total downloaded: $([math]::Round($totalSize/1MB,2)) MB" "INFO"
    Write-Log "  Log: $logfile" "INFO"
    Write-Log "================================================" "INFO"

    # Extract if requested
    if ($Extract) {
        Write-Log "=== EXTRACTING DOWNLOADED FILES ===" "INFO"

        foreach ($r in $downloadResult.Results) {
            if ($r.Success -and (Test-Path $r.LocalPath)) {
                # Determine extract path (remove .zip extension)
                $extractPath = $r.LocalPath -replace '\.zip$', ''

                Extract-ZipFile -ZipPath $r.LocalPath -DestPath $extractPath -DeleteAfter:$DeleteZipAfterExtract
            }
        }
    }

    exit $(if ($downloadResult.Failed -eq 0) { 0 } else { 1 })
}

# MODE: VERIFY
if ($Mode -eq "verify") {
    Write-Log "=== VERIFYING DOWNLOADED FILES ===" "INFO"

    $zips = Get-ChildItem $downloadDir -Filter "*.zip"

    Write-Log "Found $($zips.Count) zip files to verify" "INFO"

    $okCount = 0
    $failCount = 0

    foreach ($zip in $zips) {
        if (Verify-DownloadedFile -ZipPath $zip.FullName) {
            $okCount++
        } else {
            $failCount++
        }
    }

    Write-Log "================================================" "INFO"
    Write-Log "VERIFY COMPLETED" "INFO"
    Write-Log "  [OK] $okCount / $($zips.Count)" "INFO"
    Write-Log "  [FAIL] $failCount / $($zips.Count)" "INFO"
    Write-Log "================================================" "INFO"

    exit $(if ($failCount -eq 0) { 0 } else { 1 })
}

exit 0
