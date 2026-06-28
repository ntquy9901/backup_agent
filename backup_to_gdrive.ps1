# ============================================================
# BMAD-PROJECTS BACKUP SCRIPT - STREAMING MODE
# Zip → Upload → Delete → Next (save disk space)
# ============================================================

param(
    [string]$SourceDir = "D:\bmad-projects",
    [string]$TempDir = "D:\bmad-projects\backup_agent\temp",
    [string]$GdriveDest = "gdrive:bmad-backups",
    [int]$MaxRetries = 3
)

# ===== CONFIGURATION =====
$timestamp = Get-Date -Format "yyyyMMdd_HH:mm:ss"
$backupDate = Get-Date -Format "yyyy-MM"
$logfile = "$TempDir\backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Folders to skip
$skipFolders = @(".claude", "_bmad", "_bmad-output", "backup_agent", "temp")

# Space safety margin (1.5x the folder size for zip)
$spaceMarginMultiplier = 1.5

# Minimum free space required (MB) - safety buffer
$minFreeSpaceMB = 500

# Create temp directory
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

# ===== LOGGING FUNCTION =====
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
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
    $remotePath = "$GdriveDest/$backupDate/$zipName"

    Write-Log "=== Processing: $FolderName ===" "INFO"

    # STEP 0: CHECK DISK SPACE BEFORE ZIP
    Write-Log "  [$FolderName] Checking disk space..." "INFO"
    $folderSizeMB = Get-FolderSize -FolderPath $FolderPath

    if ($null -eq $folderSizeMB) {
        Write-Log "  [$FolderName] ⚠ Could not determine folder size, attempting anyway..." "WARNING"
        $folderSizeMB = 0
    } else {
        Write-Log "  [$FolderName] Folder size: $folderSizeMB MB" "INFO"
    }

    if (-not (Test-EnoughDiskSpace -DriveLetter "D" -RequiredSpaceMB $folderSizeMB)) {
        Write-Log "  [$FolderName] ✗ NOT ENOUGH DISK SPACE! Skipping this folder." "ERROR"
        Write-Log "  [$FolderName] → Free up space or backup manually, then retry." "ERROR"
        return "SKIPPED"
    }
    Write-Log "  [$FolderName] ✓ Disk space OK" "SUCCESS"

    # STEP 1: ZIP
    Write-Log "  [$FolderName] Zipping..." "INFO"
    try {
        # Try 7-Zip first (faster), fallback to PowerShell
        if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
            & 7z.exe a -tzip $zipPath $FolderPath -mx5 -bso0 -bsp0 > $null 2>&1
            $zipExitCode = $LASTEXITCODE
        } else {
            Compress-Archive -Path $FolderPath -DestinationPath $zipPath -Force
            $zipExitCode = 0
        }

        if ($zipExitCode -eq 0 -and (Test-Path $zipPath)) {
            $zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
            Write-Log "  [$FolderName] ✓ Zipped: $zipSize MB" "SUCCESS"
        } else {
            Write-Log "  [$FolderName] ✗ Zip failed (Exit: $zipExitCode)" "ERROR"
            return $false
        }
    } catch {
        Write-Log "  [$FolderName] ✗ Zip error: $_" "ERROR"
        return $false
    }

    # STEP 2: UPLOAD
    Write-Log "  [$FolderName] Uploading to Google Drive..." "INFO"
    $retry = 0
    $uploadSuccess = $false

    while ($retry -lt $MaxRetries -and -not $uploadSuccess) {
        $retry++
        try {
            & rclone copyto $zipPath $remotePath `
                --progress `
                --log-file $logfile `
                --log-level INFO `
                --retries 3 `
                --low-level-retries 3

            if ($LASTEXITCODE -eq 0) {
                Write-Log "  [$FolderName] ✓ Uploaded successfully" "SUCCESS"
                $uploadSuccess = $true
            } else {
                Write-Log "  [$FolderName] ⚠ Upload failed (Attempt $retry/$MaxRetries, Exit: $LASTEXITCODE)" "WARNING"
                Start-Sleep -Seconds 5
            }
        } catch {
            Write-Log "  [$FolderName] ⚠ Upload error (Attempt $retry/$MaxRetries): $_" "WARNING"
            Start-Sleep -Seconds 5
        }
    }

    if (-not $uploadSuccess) {
        Write-Log "  [$FolderName] ✗ Upload failed after $MaxRetries attempts" "ERROR"
    }

    # STEP 3: DELETE LOCAL ZIP (save disk space)
    Write-Log "  [$FolderName] Cleaning up local zip..." "INFO"
    try {
        Remove-Item $zipPath -Force -ErrorAction Stop
        Write-Log "  [$FolderName] ✓ Local zip deleted" "SUCCESS"
    } catch {
        Write-Log "  [$FolderName] ⚠ Failed to delete local zip: $_" "WARNING"
    }

    return $uploadSuccess
}

# ===== MAIN SCRIPT =====
Write-Log "================================================" "INFO"
Write-Log "BMAD PROJECTS BACKUP - STREAMING MODE" "INFO"
Write-Log "Started: $timestamp" "INFO"
Write-Log "Source: $SourceDir" "INFO"
Write-Log "Destination: $GdriveDest/$backupDate" "INFO"
Write-Log "================================================" "INFO"

# Check rclone
if (-not (Get-Command "rclone" -ErrorAction SilentlyContinue)) {
    Write-Log "✗ rclone not found! Install: winget install rclone.rclone" "ERROR"
    exit 1
}

# Initial disk space check
Write-Log "Checking initial disk space..." "INFO"
$diskInfo = Get-DiskSpaceInfo -DriveLetter "D"
if ($diskInfo) {
    Write-Log "  Drive D: - Free: $($diskInfo.FreeGB) GB / Total: $([math]::Round($diskInfo.TotalMB/1024,2)) GB" "INFO"
    if ($diskInfo.FreeGB -lt 1) {
        Write-Log "  ⚠ WARNING: Less than 1 GB free! Backup may fail." "WARNING"
    }
}

# Get folders
$folders = Get-ChildItem $SourceDir -Directory | Where-Object { $_.Name -notin $skipFolders }
Write-Log "Found $($folders.Count) folders to backup" "INFO"

# Manifest tracking
$manifest = @()
$manifest += "=== BMAD BACKUP MANIFEST ==="
$manifest += "Timestamp: $timestamp"
$manifest += "Source: $SourceDir"
$manifest += "Destination: $GdriveDest/$backupDate"
$manifest += "Total Folders: $($folders.Count)"
$manifest += ""

# Process each folder sequentially
$successCount = 0
$failCount = 0
$skippedCount = 0

foreach ($folder in $folders) {
    $result = Backup-Folder -FolderName $folder.Name -FolderPath $folder.FullName

    if ($result -eq "SKIPPED") {
        $skippedCount++
        $manifest += "⊘ $($folder.Name) | SKIPPED (insufficient disk space)"
    } elseif ($result) {
        $successCount++
        $manifest += "✓ $($folder.Name) | SUCCESS"
    } else {
        $failCount++
        $manifest += "✗ $($folder.Name) | FAILED"
    }

    $manifest += ""
}

# Save manifest
$manifestFile = "$TempDir\MANIFEST_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$manifest | Out-File -FilePath $manifestFile -Encoding UTF8
Write-Log "Manifest saved to: $manifestFile" "INFO"

# Upload manifest
Write-Log "Uploading manifest to Google Drive..." "INFO"
& rclone copyto $manifestFile "$GdriveDest/$backupDate/MANIFEST_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt" --log-level INFO

# Summary
$endTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Show final disk space
$finalDiskInfo = Get-DiskSpaceInfo -DriveLetter "D"

Write-Log "================================================" "INFO"
Write-Log "BACKUP COMPLETED: $endTime" "INFO"
Write-Log "  ✓ Success: $successCount / $($folders.Count)" "INFO"
Write-Log "  ✗ Failed: $failCount / $($folders.Count)" "INFO"
Write-Log "  ⊘ Skipped: $skippedCount / $($folders.Count)" "INFO"
if ($finalDiskInfo) {
    Write-Log "  Final free space: $($finalDiskInfo.FreeGB) GB on D:" "INFO"
}
Write-Log "  Log: $logfile" "INFO"
Write-Log "================================================" "INFO"

# Exit code
exit $(if ($failCount -eq 0) { 0 } else { 1 })
