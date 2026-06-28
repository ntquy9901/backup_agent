# ============================================================
# BMAD-PROJECTS BACKUP SCRIPT - CONFIG-DRIVEN VERSION
# Reads settings from config.json
# ============================================================

param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
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
$SourceDir = $config.paths.sourceDir
$TempDir = $config.paths.tempDir
$GdriveRemote = $config.paths.gdriveRemote
$GdriveDest = $config.paths.gdriveDest
$mode = $config.mode.type
$skipFolders = $config.folders.skipList

# Step flags
$checkDiskSpace = $config.steps.checkDiskSpace
$zipFolders = $config.steps.zipFolders
$uploadToGdrive = $config.steps.uploadToGdrive
$deleteLocalZip = $config.steps.deleteLocalZip
$uploadManifest = $config.steps.uploadManifest

# Space check config
$spaceMarginMultiplier = $config.spaceCheck.marginMultiplier
$minFreeSpaceMB = $config.spaceCheck.minFreeSpaceMB
$spaceFailAction = $config.spaceCheck.failAction

# Upload config
$maxRetries = $config.upload.maxRetries
$retryDelaySeconds = $config.upload.retryDelaySeconds
$parallelUploads = $config.upload.parallelUploads
$batchSize = $config.upload.batchSize

# Test mode
$testEnabled = $config.test.enabled
$maxFoldersToProcess = $config.test.maxFoldersToProcess

# ===== CONFIGURATION =====
$timestamp = Get-Date -Format "yyyyMMdd_HH:mm:ss"
$backupDate = Get-Date -Format "yyyy-MM"
$logfile = "$TempDir\backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Create temp directory
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

# ===== LOGGING FUNCTION =====
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")

    # Check if we should log this level
    $logLevels = @("DEBUG", "INFO", "WARNING", "ERROR")
    $currentLevelIdx = $logLevels.IndexOf($config.logging.level)
    $msgLevelIdx = $logLevels.IndexOf($Level)

    if ($msgLevelIdx -lt $currentLevelIdx -and $Level -ne "ERROR") {
        return
    }

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$ts] [$Level] $Message"
    Write-Host $logMsg
    Add-Content -Path $logfile -Value $logMsg
}

# ===== DISK SPACE CHECK FUNCTION =====
function Get-DiskSpaceInfo {
    param([string]$DriveLetter = "D")

    try {
        $drive = Get-PSDrive -Name $DriveLetter -ErrorAction Stop
        $freeSpaceMB = [math]::Round($drive.Free / 1MB, 2)
        $usedSpaceMB = [math]::Round($drive.Used / 1MB, 2)
        $totalSpaceMB = [math]::Round(($drive.Free + $drive.Used) / 1MB, 2)

        return @{
            FreeMB = $freeSpaceMB
            UsedMB = $usedSpaceMB
            TotalMB = $totalSpaceMB
            FreeGB = [math]::Round($freeSpaceMB / 1024, 2)
        }
    } catch {
        Write-Log "Failed to get disk info for drive $DriveLetter`: $_" "ERROR"
        return $null
    }
}

function Get-FolderSize {
    param([string]$FolderPath)

    try {
        $size = (Get-ChildItem $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
        return [math]::Round($size / 1MB, 2)
    } catch {
        Write-Log "Failed to calculate folder size for $FolderPath`: $_" "WARNING"
        return $null
    }
}

function Test-EnoughDiskSpace {
    param([string]$DriveLetter = "D",
          [double]$RequiredSpaceMB)

    $diskInfo = Get-DiskSpaceInfo -DriveLetter $DriveLetter

    if ($null -eq $diskInfo) {
        return $false
    }

    $requiredWithMargin = $RequiredSpaceMB * $spaceMarginMultiplier + $minFreeSpaceMB
    $hasEnoughSpace = $diskInfo.FreeMB -gt $requiredWithMargin

    Write-Log "  [SPACE CHECK] Drive $DriveLetter`: Free = $($diskInfo.FreeGB) GB, Required = $([math]::Round($requiredWithMargin/1024,2)) GB" "INFO"

    return $hasEnoughSpace
}

# ===== MAIN BACKUP FUNCTION =====
function Backup-Folder {
    param([string]$FolderName, [string]$FolderPath)

    $zipName = "bmad-$FolderName`_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    $zipPath = Join-Path $TempDir $zipName
    $remotePath = "$GdriveRemote`:$GdriveDest/$backupDate/$zipName"

    Write-Log "=== Processing: $FolderName ===" "INFO"

    # STEP 0: CHECK DISK SPACE (if enabled)
    if ($checkDiskSpace) {
        Write-Log "  [$FolderName] Checking disk space..." "INFO"
        $folderSizeMB = Get-FolderSize -FolderPath $FolderPath

        if ($null -eq $folderSizeMB) {
            Write-Log "  [$FolderName] [!] Could not determine folder size, attempting anyway..." "WARNING"
            $folderSizeMB = 0
        } else {
            Write-Log "  [$FolderName] Folder size: $folderSizeMB MB" "INFO"
        }

        if (-not (Test-EnoughDiskSpace -DriveLetter "D" -RequiredSpaceMB $folderSizeMB)) {
            Write-Log "  [$FolderName] [FAIL] NOT ENOUGH DISK SPACE! Skipping this folder." "ERROR"
            Write-Log "  [$FolderName] => Free up space or backup manually, then retry." "ERROR"

            if ($spaceFailAction -eq "stop") {
                Write-Log "!!! STOPPING BACKUP (configured to stop on space error) !!!" "ERROR"
                exit 1
            }
            return "SKIPPED"
        }
        Write-Log "  [$FolderName] [OK] Disk space OK" "SUCCESS"
    }

    # STEP 1: ZIP (if enabled)
    if ($zipFolders) {
        Write-Log "  [$FolderName] Zipping..." "INFO"
        try {
            if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
                & 7z.exe a -tzip $zipPath $FolderPath -mx$config.zip.compressionLevel -bso0 -bsp0 > $null 2>&1
                $zipExitCode = $LASTEXITCODE
            } else {
                Compress-Archive -Path $FolderPath -DestinationPath $zipPath -Force
                $zipExitCode = 0
            }

            if ($zipExitCode -eq 0 -and (Test-Path $zipPath)) {
                $zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
                Write-Log "  [$FolderName] [OK] Zipped: $zipSize MB" "SUCCESS"
            } else {
                Write-Log "  [$FolderName] [FAIL] Zip failed (Exit: $zipExitCode)" "ERROR"
                return $false
            }
        } catch {
            Write-Log "  [$FolderName] [FAIL] Zip error: $_" "ERROR"
            return $false
        }
    }

    # STEP 2: UPLOAD (if enabled)
    if ($uploadToGdrive) {
        Write-Log "  [$FolderName] Uploading to Google Drive..." "INFO"
        $retry = 0
        $uploadSuccess = $false

        while ($retry -lt $maxRetries -and -not $uploadSuccess) {
            $retry++
            try {
                & rclone copyto $zipPath $remotePath `
                    --progress `
                    --log-file $logfile `
                    --log-level INFO `
                    --retries 3 `
                    --low-level-retries 3

                if ($LASTEXITCODE -eq 0) {
                    Write-Log "  [$FolderName] [OK] Uploaded successfully" "SUCCESS"
                    $uploadSuccess = $true
                } else {
                    Write-Log "  [$FolderName] [!] Upload failed (Attempt $retry/$maxRetries, Exit: $LASTEXITCODE)" "WARNING"
                    Start-Sleep -Seconds $retryDelaySeconds
                }
            } catch {
                Write-Log "  [$FolderName] [!] Upload error (Attempt $retry/$maxRetries): $_" "WARNING"
                Start-Sleep -Seconds $retryDelaySeconds
            }
        }

        if (-not $uploadSuccess) {
            Write-Log "  [$FolderName] [FAIL] Upload failed after $maxRetries attempts" "ERROR"
        }
    } else {
        $uploadSuccess = $true  # Skipped but considered success
        Write-Log "  [$FolderName] => Upload skipped (disabled in config)" "INFO"
    }

    # STEP 3: DELETE LOCAL ZIP (if enabled)
    if ($deleteLocalZip -and $zipFolders) {
        Write-Log "  [$FolderName] Cleaning up local zip..." "INFO"
        try {
            Remove-Item $zipPath -Force -ErrorAction Stop
            Write-Log "  [$FolderName] [OK] Local zip deleted" "SUCCESS"
        } catch {
            Write-Log "  [$FolderName] [!] Failed to delete local zip: $_" "WARNING"
        }
    } elseif (-not $deleteLocalZip) {
        Write-Log "  [$FolderName] => Local zip kept (disabled in config)" "INFO"
    }

    return $uploadSuccess
}

# ===== PARALLEL STREAMING MODE FUNCTION =====
function Backup-ParallelStreamingMode {
    param([array]$Folders, [int]$BatchSize = 3)

    Write-Log "=== PARALLEL STREAMING MODE: Process $BatchSize folders simultaneously ===" "INFO"
    Write-Log "Batch size: $BatchSize (zip+upload in parallel)" "INFO"

    $successCount = 0
    $failCount = 0
    $skippedCount = 0
    $results = @()

    # Process folders in batches
    for ($i = 0; $i -lt $Folders.Count; $i += $BatchSize) {
        $batch = $Folders[$i..[Math]::Min($i + $BatchSize - 1, $Folders.Count - 1)]
        Write-Log "Processing batch $([Math]::Floor($i / $BatchSize) + 1): $($batch.Count) folders" "INFO"

        # Create runspaces for parallel processing
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $batch.Count)
        $runspacePool.Open()

        $jobs = @()
        foreach ($folder in $batch) {
            $powershell = [powershell]::Create()
            $powershell.RunspacePool = $runspacePool

            # Add parameters to script
            [void]$powershell.AddScript({
                param($FolderName, $FolderPath, $TempDir, $GdriveRemote, $GdriveDest, $backupDate,
                      $checkDiskSpace, $zipFolders, $uploadToGdrive, $deleteLocalZip,
                      $spaceMarginMultiplier, $minFreeSpaceMB, $maxRetries, $retryDelaySeconds,
                      $compressionLevel, $config)

                $zipName = "bmad-$FolderName`_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
                $zipPath = Join-Path $TempDir $zipName
                $remotePath = "$GdriveRemote`:$GdriveDest/$backupDate/$zipName"

                $result = @{
                    Folder = $FolderName
                    Status = "UNKNOWN"
                    ZipSize = 0
                    Error = ""
                }

                # Space check
                if ($checkDiskSpace) {
                    try {
                        $folderSize = (Get-ChildItem $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
                                     Measure-Object -Property Length -Sum).Sum / 1MB
                        $drive = Get-PSDrive -Name "D"
                        $requiredSpace = ($folderSize * $spaceMarginMultiplier) + $minFreeSpaceMB

                        if ($drive.Free -lt ($requiredSpace * 1MB)) {
                            $result.Status = "SKIPPED"
                            $result.Error = "Not enough disk space"
                            return $result
                        }
                    } catch {
                        # Continue anyway
                    }
                }

                # Zip
                if ($zipFolders) {
                    try {
                        if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
                            & 7z.exe a -tzip $zipPath $FolderPath -mx$compressionLevel -bso0 -bsp0 > $null 2>&1
                        } else {
                            Compress-Archive -Path $FolderPath -DestinationPath $zipPath -Force
                        }

                        if (Test-Path $zipPath) {
                            $result.ZipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
                        } else {
                            $result.Status = "FAILED"
                            $result.Error = "Zip failed"
                            return $result
                        }
                    } catch {
                        $result.Status = "FAILED"
                        $result.Error = $_.Exception.Message
                        return $result
                    }
                }

                # Upload
                if ($uploadToGdrive -and $zipFolders) {
                    $retry = 0
                    $uploadSuccess = $false

                    while ($retry -lt $maxRetries -and -not $uploadSuccess) {
                        $retry++
                        & rclone copyto $zipPath $remotePath --retries 3 --log-level ERROR 2>&1 | Out-Null

                        if ($LASTEXITCODE -eq 0) {
                            $uploadSuccess = $true
                        } else {
                            Start-Sleep -Seconds $retryDelaySeconds
                        }
                    }

                    if (-not $uploadSuccess) {
                        $result.Status = "FAILED"
                        $result.Error = "Upload failed"
                        return $result
                    }
                }

                # Delete local zip
                if ($deleteLocalZip -and $zipFolders) {
                    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                }

                $result.Status = "SUCCESS"
                return $result
            }).AddParameter("FolderName", $folder.Name).AddParameter("FolderPath", $folder.FullName).AddParameter("TempDir", $TempDir).AddParameter("GdriveRemote", $GdriveRemote).AddParameter("GdriveDest", $GdriveDest).AddParameter("backupDate", $backupDate).AddParameter("checkDiskSpace", $checkDiskSpace).AddParameter("zipFolders", $zipFolders).AddParameter("uploadToGdrive", $uploadToGdrive).AddParameter("deleteLocalZip", $deleteLocalZip).AddParameter("spaceMarginMultiplier", $spaceMarginMultiplier).AddParameter("minFreeSpaceMB", $minFreeSpaceMB).AddParameter("maxRetries", $maxRetries).AddParameter("retryDelaySeconds", $retryDelaySeconds).AddParameter("compressionLevel", $config.zip.compressionLevel).AddParameter("config", $config)

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
            $r = $jobResult
            $results += $r

            switch ($r.Status) {
                "SUCCESS" {
                    Write-Log "  [$($r.Folder)] SUCCESS - Zip: $($r.ZipSize) MB" "SUCCESS"
                    $successCount++
                }
                "SKIPPED" {
                    Write-Log "  [$($r.Folder)] SKIPPED - $($r.Error)" "WARNING"
                    $skippedCount++
                }
                "FAILED" {
                    Write-Log "  [$($r.Folder)] FAILED - $($r.Error)" "ERROR"
                    $failCount++
                }
            }
        }

        # Small delay between batches
        if ($i + $BatchSize -lt $Folders.Count) {
            Start-Sleep -Seconds 1
        }
    }

    return @{
        Success = $successCount
        Failed = $failCount
        Skipped = $skippedCount
        Results = $results
    }
}

# ===== BATCH MODE FUNCTION =====
function Backup-BatchMode {
    param([array]$Folders)

    Write-Log "=== BATCH MODE: Zip all first, then upload all ===" "INFO"

    $zips = @()

    # Phase 1: Zip all folders
    Write-Log "Phase 1: Zipping all folders..." "INFO"
    foreach ($folder in $Folders) {
        if ($checkDiskSpace) {
            $folderSizeMB = Get-FolderSize -FolderPath $folder.FullName
            if (-not (Test-EnoughDiskSpace -DriveLetter "D" -RequiredSpaceMB $folderSizeMB)) {
                Write-Log "  [$($folder.Name)] [FAIL] Skipped (not enough space)" "ERROR"
                continue
            }
        }

        $zipName = "bmad-$($folder.Name)_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
        $zipPath = Join-Path $TempDir $zipName

        Write-Log "  Zipping: $($folder.Name)..." "INFO"

        if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
            & 7z.exe a -tzip $zipPath $folder.FullName -mx$config.zip.compressionLevel -bso0 -bsp0 > $null 2>&1
        } else {
            Compress-Archive -Path $folder.FullName -DestinationPath $zipPath -Force
        }

        if (Test-Path $zipPath) {
            $zips += @{Path = $zipPath; Name = $zipName; Folder = $folder.Name}
            Write-Log "  [OK] Zipped: $($folder.Name)" "SUCCESS"
        }
    }

    # Phase 2: Upload all zips
    Write-Log "Phase 2: Uploading all zips..." "INFO"

    # Upload with parallel transfers using rclone
    $rcloneTransfers = $config.upload.transfers
    foreach ($zip in $zips) {
        $remotePath = "$GdriveRemote`:$GdriveDest/$backupDate/$($zip.Name)"
        Write-Log "  Uploading: $($zip.Name)..." "INFO"

        & rclone copyto $zip.Path $remotePath --log-file $logfile --log-level INFO --transfers $rcloneTransfers

        if ($LASTEXITCODE -eq 0) {
            Write-Log "  [OK] Uploaded: $($zip.Name)" "SUCCESS"
        } else {
            Write-Log "  [FAIL] Upload failed: $($zip.Name)" "ERROR"
        }
    }

    # Phase 3: Delete all zips (if enabled)
    if ($deleteLocalZip) {
        Write-Log "Phase 3: Cleaning up local zips..." "INFO"
        foreach ($zip in $zips) {
            Remove-Item $zip.Path -Force -ErrorAction SilentlyContinue
        }
        Write-Log "  [OK] Cleaned up $($zips.Count) zip files" "SUCCESS"
    }

    return $zips.Count
}

# ===== MAIN SCRIPT =====
Write-Log "================================================" "INFO"
Write-Log "BMAD PROJECTS BACKUP - CONFIG-DRIVEN MODE" "INFO"
Write-Log "Config: $ConfigPath" "INFO"
Write-Log "Mode: $mode" "INFO"
Write-Log "Started: $timestamp" "INFO"
Write-Log "Source: $SourceDir" "INFO"
Write-Log "Destination: $GdriveRemote`:$GdriveDest/$backupDate" "INFO"
Write-Log "================================================" "INFO"

# Check rclone
if (-not (Get-Command "rclone" -ErrorAction SilentlyContinue)) {
    Write-Log "[FAIL] rclone not found! Install: winget install rclone.rclone" "ERROR"
    exit 1
}

# Initial disk space check
if ($checkDiskSpace) {
    Write-Log "Checking initial disk space..." "INFO"
    $diskInfo = Get-DiskSpaceInfo -DriveLetter "D"
    if ($diskInfo) {
        Write-Log "  Drive D: - Free: $($diskInfo.FreeGB) GB / Total: $([math]::Round($diskInfo.TotalMB/1024,2)) GB" "INFO"
        if ($diskInfo.FreeGB -lt 1) {
            Write-Log "  [!] WARNING: Less than 1 GB free! Backup may fail." "WARNING"
        }
    }
}

# Get folders
$folders = Get-ChildItem $SourceDir -Directory | Where-Object { $_.Name -notin $skipFolders }
Write-Log "Found $($folders.Count) folders to backup" "INFO"

# Test mode: limit folders
if ($testEnabled) {
    Write-Log "=== TEST MODE: Processing only $maxFoldersToProcess folder(s) ===" "WARNING"
    $folders = $folders | Select-Object -First $maxFoldersToProcess
}

# Manifest tracking
$manifest = @()
$manifest += "=== BMAD BACKUP MANIFEST ==="
$manifest += "Timestamp: $timestamp"
$manifest += "Config: $ConfigPath"
$manifest += "Mode: $mode"
$manifest += "Source: $SourceDir"
$manifest += "Destination: $GdriveRemote`:$GdriveDest/$backupDate"
$manifest += "Total Folders: $($folders.Count)"
$manifest += ""

# Process based on mode
$successCount = 0
$failCount = 0
$skippedCount = 0

if ($mode -eq "batch") {
    # Batch mode: zip all, upload all, delete all
    $batchCount = Backup-BatchMode -Folders $folders
    $successCount = $batchCount
    $failCount = $folders.Count - $batchCount
} elseif ($mode -eq "parallel" -and $parallelUploads) {
    # Parallel streaming mode: process multiple folders simultaneously
    $parallelResult = Backup-ParallelStreamingMode -Folders $folders -BatchSize $batchSize
    $successCount = $parallelResult.Success
    $failCount = $parallelResult.Failed
    $skippedCount = $parallelResult.Skipped

    # Add results to manifest
    foreach ($r in $parallelResult.Results) {
        switch ($r.Status) {
            "SUCCESS" { $manifest += "[OK] $($r.Folder) | SUCCESS | Zip: $($r.ZipSize) MB" }
            "SKIPPED" { $manifest += "[SKIP] $($r.Folder) | SKIPPED | $($r.Error)" }
            "FAILED" { $manifest += "[FAIL] $($r.Folder) | FAILED | $($r.Error)" }
        }
        $manifest += ""
    }
} else {
    # Streaming mode: zip => upload => delete per folder
    foreach ($folder in $folders) {
        $result = Backup-Folder -FolderName $folder.Name -FolderPath $folder.FullName

        if ($result -eq "SKIPPED") {
            $skippedCount++
            $manifest += "[SKIP] $($folder.Name) | SKIPPED (insufficient disk space)"
        } elseif ($result) {
            $successCount++
            $manifest += "[OK] $($folder.Name) | SUCCESS"
        } else {
            $failCount++
            $manifest += "[FAIL] $($folder.Name) | FAILED"
        }

        $manifest += ""
    }
}

# Save manifest
$manifestFile = "$TempDir\MANIFEST_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$manifest | Out-File -FilePath $manifestFile -Encoding UTF8
Write-Log "Manifest saved to: $manifestFile" "INFO"

# Upload manifest (if enabled)
if ($uploadManifest) {
    Write-Log "Uploading manifest to Google Drive..." "INFO"
    & rclone copyto $manifestFile "$GdriveRemote`:$GdriveDest/$backupDate/MANIFEST_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt" --log-level INFO
}

# Summary
$endTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$finalDiskInfo = Get-DiskSpaceInfo -DriveLetter "D"

Write-Log "================================================" "INFO"
Write-Log "BACKUP COMPLETED: $endTime" "INFO"
Write-Log "  [OK] Success: $successCount / $($folders.Count)" "INFO"
Write-Log "  [FAIL] Failed: $failCount / $($folders.Count)" "INFO"
Write-Log "  [SKIP] Skipped: $skippedCount / $($folders.Count)" "INFO"
if ($finalDiskInfo) {
    Write-Log "  Final free space: $($finalDiskInfo.FreeGB) GB on D:" "INFO"
}
Write-Log "  Log: $logfile" "INFO"
Write-Log "================================================" "INFO"

# Exit code
exit $(if ($failCount -eq 0) { 0 } else { 1 })
