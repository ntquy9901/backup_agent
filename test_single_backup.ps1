# ============================================================
# TEST: Single Folder Backup (End-to-End)
# ============================================================

param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [string]$TestFolderName = ""
)

$ErrorActionPreference = "Stop"

# Load config
if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath | ConvertFrom-Json
} else {
    Write-Host "Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

function Write-TestResult {
    param([string]$Test, [bool]$Passed, [string]$Message)
    $status = if ($Passed) { "[PASS]" } else { "[FAIL]" }
    $color = if ($Passed) { "Green" } else { "Red" }
    Write-Host "[$status] $Test" -ForegroundColor $color
    if ($Message) {
        Write-Host "      -> $Message" -ForegroundColor $(if ($Passed) { "Gray" } else { "Red" })
    }
}

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "TEST: Single Folder Backup (End-to-End)" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

$allPassed = $true

# Find test folder
$sourceDir = $config.paths.sourceDir

if ([string]::IsNullOrWhiteSpace($TestFolderName)) {
    Write-Host "Selecting test folder (smallest folder)..." -ForegroundColor Yellow
    $folders = Get-ChildItem $sourceDir -Directory |
               Where-Object { $_.Name -notin $config.folders.skipList }

    if ($folders.Count -eq 0) {
        Write-Host "No folders found to test!" -ForegroundColor Red
        exit 1
    }

    $testFolder = $folders | Sort-Object {
        try { (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
        catch { 0 }
    } | Select-Object -First 1

    $TestFolderName = $testFolder.Name
    $testFolderPath = $testFolder.FullName
} else {
    $testFolderPath = Join-Path $sourceDir $TestFolderName
    if (-not (Test-Path $testFolderPath)) {
        Write-Host "Folder not found: $testFolderPath" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Test folder: $TestFolderName" -ForegroundColor Cyan

# Calculate folder size
Write-Host "`nTest 0: Calculate folder size..." -ForegroundColor Yellow
try {
    $folderSize = (Get-ChildItem $testFolderPath -Recurse -File -ErrorAction SilentlyContinue |
                   Measure-Object -Property Length -Sum).Sum
    $folderSizeMB = [math]::Round($folderSize / 1MB, 2)
    Write-TestResult "Folder size" $true "$folderSizeMB MB"
} catch {
    Write-TestResult "Folder size" $false $_.Exception.Message
    $folderSizeMB = 0
}

# STEP 1: Check disk space
Write-Host "`nTest 1: Check disk space..." -ForegroundColor Yellow
if ($config.steps.checkDiskSpace) {
    try {
        $drive = Get-PSDrive -Name "D"
        $freeSpaceMB = [math]::Round($drive.Free / 1MB, 2)
        $requiredSpaceMB = ($folderSizeMB * $config.spaceCheck.marginMultiplier) + $config.spaceCheck.minFreeSpaceMB
        $freeSpaceGB = [math]::Round($freeSpaceMB / 1024, 2)
        $requiredSpaceGB = [math]::Round($requiredSpaceMB / 1024, 2)

        if ($freeSpaceMB -gt $requiredSpaceMB) {
            Write-TestResult "Disk space check" $true "Free: $freeSpaceGB GB >= Required: $requiredSpaceGB GB"
        } else {
            Write-TestResult "Disk space check" $false "Free: $freeSpaceGB GB < Required: $requiredSpaceGB GB"
            $allPassed = $false
        }
    } catch {
        Write-TestResult "Disk space check" $false $_.Exception.Message
        $allPassed = $false
    }
} else {
    Write-TestResult "Disk space check" $true "Skipped (disabled in config)"
}

# STEP 2: Zip folder
Write-Host "`nTest 2: Zip folder..." -ForegroundColor Yellow
if ($config.steps.zipFolders) {
    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $zipName = "bmad-$TestFolderName`_$timestamp.zip"
        $tempDir = $config.paths.tempDir
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        $zipPath = Join-Path $tempDir $zipName

        if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
            & 7z.exe a -tzip $zipPath $testFolderPath -mx$config.zip.compressionLevel -bso0 -bsp0 > $null 2>&1
            $exitCode = $LASTEXITCODE
        } else {
            Compress-Archive -Path $testFolderPath -DestinationPath $zipPath -Force
            $exitCode = 0
        }

        if ($exitCode -eq 0 -and (Test-Path $zipPath)) {
            $zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
            Write-TestResult "Zip folder" $true "Created: $zipSize MB"
        } else {
            Write-TestResult "Zip folder" $false "Exit code: $exitCode"
            $allPassed = $false
            $zipPath = $null
        }
    } catch {
        Write-TestResult "Zip folder" $false $_.Exception.Message
        $allPassed = $false
        $zipPath = $null
    }
} else {
    Write-TestResult "Zip folder" $true "Skipped (disabled in config)"
    $zipPath = $null
}

# STEP 3: Upload to Google Drive
Write-Host "`nTest 3: Upload to Google Drive..." -ForegroundColor Yellow
if ($config.steps.uploadToGdrive -and $zipPath) {
    try {
        $remote = $config.paths.gdriveRemote
        $destFolder = "$($config.paths.gdriveDest)/test"
        $remotePath = "$remote`:$destFolder/$zipName"

        & rclone copyto $zipPath $remotePath --log-level ERROR 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-TestResult "Upload to GDrive" $true "Uploaded to: $remotePath"
        } else {
            Write-TestResult "Upload to GDrive" $false "Exit code: $LASTEXITCODE"
            $allPassed = $false
        }
    } catch {
        Write-TestResult "Upload to GDrive" $false $_.Exception.Message
        $allPassed = $false
    }
} elseif (-not $config.steps.uploadToGdrive) {
    Write-TestResult "Upload to GDrive" $true "Skipped (disabled in config)"
} else {
    Write-TestResult "Upload to GDrive" $false "No zip file to upload"
    $allPassed = $false
}

# STEP 4: Verify uploaded file
Write-Host "`nTest 4: Verify uploaded file..." -ForegroundColor Yellow
if ($config.steps.uploadToGdrive -and $zipPath) {
    try {
        $remote = $config.paths.gdriveRemote
        $destFolder = "$($config.paths.gdriveDest)/test"
        $remotePath = "$remote`:$destFolder/$zipName"

        $result = & rclone size "$remotePath" --log-level ERROR 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-TestResult "Verify upload" $true "File exists on Google Drive"
        } else {
            Write-TestResult "Verify upload" $false "File not found"
            $allPassed = $false
        }
    } catch {
        Write-TestResult "Verify upload" $false $_.Exception.Message
        $allPassed = $false
    }
} else {
    Write-TestResult "Verify upload" $true "Skipped (upload disabled)"
}

# STEP 5: Delete local zip
Write-Host "`nTest 5: Delete local zip..." -ForegroundColor Yellow
if ($config.steps.deleteLocalZip -and $zipPath) {
    try {
        if (Test-Path $zipPath) {
            Remove-Item $zipPath -Force
            if (-not (Test-Path $zipPath)) {
                Write-TestResult "Delete local zip" $true "Zip file deleted"
            } else {
                Write-TestResult "Delete local zip" $false "File still exists"
                $allPassed = $false
            }
        } else {
            Write-TestResult "Delete local zip" $true "No zip to delete"
        }
    } catch {
        Write-TestResult "Delete local zip" $false $_.Exception.Message
        $allPassed = $false
    }
} else {
    Write-TestResult "Delete local zip" $true "Skipped (disabled in config)"
}

# STEP 6: Cleanup test file from Google Drive
Write-Host "`nTest 6: Cleanup test file from Google Drive..." -ForegroundColor Yellow
try {
    $remote = $config.paths.gdriveRemote
    $destFolder = "$($config.paths.gdriveDest)/test"
    & rclone delete "$remote`:$destFolder" --log-level ERROR 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-TestResult "Cleanup GDrive test" $true "Test folder removed"
    } else {
        Write-TestResult "Cleanup GDrive test" $false "Exit code: $LASTEXITCODE"
    }
} catch {
    Write-TestResult "Cleanup GDrive test" $false $_.Exception.Message
}

# Summary
Write-Host "`n================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
    Write-Host "End-to-end backup is working!" -ForegroundColor Green
    Write-Host "`nYou can now run the full backup." -ForegroundColor Cyan
} else {
    Write-Host "SOME TESTS FAILED" -ForegroundColor Red
    Write-Host "Please check the issues above." -ForegroundColor Red
}
Write-Host "================================================`n" -ForegroundColor Cyan

exit $(if ($allPassed) { 0 } else { 1 })
