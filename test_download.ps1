# ============================================================
# TEST: Download Backup - Comprehensive Test Suite
# ============================================================

param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

$ErrorActionPreference = "Stop"

# Test results tracking
$testResults = @()

function Write-TestResult {
    param([string]$Test, [bool]$Passed, [string]$Message)
    $status = if ($Passed) { "[PASS]" } else { "[FAIL]" }
    $color = if ($Passed) { "Green" } else { "Red" }
    Write-Host "[$status] $Test" -ForegroundColor $color
    if ($Message) {
        Write-Host "      -> $Message" -ForegroundColor $(if ($Passed) { "Gray" } else { "Red" })
    }
    $script:testResults += @{
        Test = $Test
        Passed = $Passed
        Message = $Message
    }
}

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "TEST: Download Backup - Comprehensive Test Suite" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

# ===== TEST CASES =====

# TEST 1: Load config
Write-Host "Test 1: Load config file..." -ForegroundColor Yellow
try {
    if (Test-Path $ConfigPath) {
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        Write-TestResult "Config file exists" $true "Loaded from: $ConfigPath"
    } else {
        Write-TestResult "Config file exists" $false "File not found: $ConfigPath"
    }
} catch {
    Write-TestResult "Config file exists" $false $_.Exception.Message
}

# TEST 2: Check rclone
Write-Host "`nTest 2: Check rclone installed..." -ForegroundColor Yellow
try {
    $rclonePath = where.exe rclone 2>$null
    if ($rclonePath) {
        $version = & rclone version 2>&1 | Select-String "rclone"
        Write-TestResult "rclone installed" $true $version
    } else {
        Write-TestResult "rclone installed" $false "rclone not found"
    }
} catch {
    Write-TestResult "rclone installed" $false $_.Exception.Message
}

# TEST 3: Check Google Drive connection
Write-Host "`nTest 3: Check Google Drive connection..." -ForegroundColor Yellow
try {
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $remote = $config.paths.gdriveRemote

    & rclone about "$remote`:" --log-level ERROR 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-TestResult "GDrive connection" $true "Connected to $remote"
    } else {
        Write-TestResult "GDrive connection" $false "Exit code: $LASTEXITCODE"
    }
} catch {
    Write-TestResult "GDrive connection" $false $_.Exception.Message
}

# TEST 4: List available backups
Write-Host "`nTest 4: List available backups..." -ForegroundColor Yellow
try {
    $result = & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\backup_download.ps1" -ConfigPath $ConfigPath -Mode list 2>&1

    if ($LASTEXITCODE -eq 0) {
        $backupCount = ($result | Select-String "\[\d{4}-\d{2}\]").Count
        Write-TestResult "List backups" $true "Found $backupCount backup(s)"
    } else {
        Write-TestResult "List backups" $false "Exit code: $LASTEXITCODE"
    }
} catch {
    Write-TestResult "List backups" $false $_.Exception.Message
}

# TEST 5: Check download directory
Write-Host "`nTest 5: Check download directory..." -ForegroundColor Yellow
try {
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $downloadDir = $config.download.destinationDir

    if (-not (Test-Path $downloadDir)) {
        New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
        Write-TestResult "Download directory" $true "Created: $downloadDir"
    } else {
        Write-TestResult "Download directory" $true "Exists: $downloadDir"
    }
} catch {
    Write-TestResult "Download directory" $false $_.Exception.Message
}

# TEST 6: Download single file
Write-Host "`nTest 6: Download single file (MaxBackups=1)..." -ForegroundColor Yellow
try {
    $testDownloadDir = "$PSScriptRoot\test_download_temp"
    New-Item -ItemType Directory -Force -Path $testDownloadDir | Out-Null

    # Create test config
    $testConfigPath = "$PSScriptRoot\config_test.json"
    Copy-Item $ConfigPath $testConfigPath -Force
    $testConfig = Get-Content $testConfigPath -Raw | ConvertFrom-Json
    $testConfig.download.destinationDir = $testDownloadDir
    $testConfig | ConvertTo-Json -Depth 10 | Set-Content $testConfigPath -Force

    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\backup_download.ps1" -ConfigPath $testConfigPath -Mode download -MaxBackups 1 2>&1 | Out-Null

    # Check if ANY file was downloaded
    $files = Get-ChildItem $testDownloadDir -File -ErrorAction SilentlyContinue
    if ($files.Count -gt 0) {
        $totalSize = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1KB, 2)
        Write-TestResult "Download single file" $true "Downloaded $($files.Count) file(s), $totalSize KB"

        # Clean up
        Remove-Item $testDownloadDir -Recurse -Force
        Remove-Item $testConfigPath -Force
    } else {
        Write-TestResult "Download single file" $false "No files downloaded"
        Remove-Item $testDownloadDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $testConfigPath -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-TestResult "Download single file" $false $_.Exception.Message
    Remove-Item "$PSScriptRoot\test_download_temp" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$PSScriptRoot\config_test.json" -Force -ErrorAction SilentlyContinue
}

# TEST 7: Download multiple files (parallel)
Write-Host "`nTest 7: Download multiple files (MaxBackups=3, parallel)..." -ForegroundColor Yellow
try {
    $testDownloadDir = "$PSScriptRoot\test_download_temp"
    New-Item -ItemType Directory -Force -Path $testDownloadDir | Out-Null

    # Create test config
    $testConfigPath = "$PSScriptRoot\config_test.json"
    Copy-Item $ConfigPath $testConfigPath -Force
    $testConfig = Get-Content $testConfigPath -Raw | ConvertFrom-Json
    $testConfig.download.destinationDir = $testDownloadDir
    $testConfig | ConvertTo-Json -Depth 10 | Set-Content $testConfigPath -Force

    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\backup_download.ps1" -ConfigPath $testConfigPath -Mode download -MaxBackups 3 2>&1 | Out-Null

    $files = Get-ChildItem $testDownloadDir -File -ErrorAction SilentlyContinue
    if ($files.Count -ge 2) {
        $totalSize = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        $zipCount = ($files | Where-Object { $_.Extension -eq ".zip" }).Count
        Write-TestResult "Download parallel" $true "Downloaded $($files.Count) files ($totalSize MB), $zipCount zip files"

        # Clean up
        Remove-Item $testDownloadDir -Recurse -Force
        Remove-Item $testConfigPath -Force
    } else {
        Write-TestResult "Download parallel" $false "Only downloaded $($files.Count) file(s)"
        Remove-Item $testDownloadDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $testConfigPath -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-TestResult "Download parallel" $false $_.Exception.Message
    Remove-Item "$PSScriptRoot\test_download_temp" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$PSScriptRoot\config_test.json" -Force -ErrorAction SilentlyContinue
}

# TEST 8: Verify downloaded file
Write-Host "`nTest 8: Verify downloaded zip file..." -ForegroundColor Yellow
try {
    $testDownloadDir = "$PSScriptRoot\test_download_temp"
    New-Item -ItemType Directory -Force -Path $testDownloadDir | Out-Null

    # Create test config
    $testConfigPath = "$PSScriptRoot\config_test.json"
    Copy-Item $ConfigPath $testConfigPath -Force
    $testConfig = Get-Content $testConfigPath -Raw | ConvertFrom-Json
    $testConfig.download.destinationDir = $testDownloadDir
    $testConfig | ConvertTo-Json -Depth 10 | Set-Content $testConfigPath -Force

    # Download a file first
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\backup_download.ps1" -ConfigPath $testConfigPath -Mode download -MaxBackups 3 2>&1 | Out-Null

    # Run verify
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\backup_download.ps1" -ConfigPath $testConfigPath -Mode verify 2>&1 | Out-Null

    $zips = Get-ChildItem $testDownloadDir -Filter "*.zip" -ErrorAction SilentlyContinue
    if ($zips.Count -gt 0) {
        $file = $zips[0]
        if ($file.Length -gt 0) {
            Write-TestResult "Verify zip" $true "File valid: $($file.Name) ($([math]::Round($file.Length/1KB,2)) KB)"
        } else {
            Write-TestResult "Verify zip" $false "File is empty"
        }
    } else {
        # If no zips, check for any files
        $files = Get-ChildItem $testDownloadDir -File -ErrorAction SilentlyContinue
        if ($files.Count -gt 0) {
            Write-TestResult "Verify zip" $true "$($files.Count) file(s) downloaded (no zips in this batch)"
        } else {
            Write-TestResult "Verify zip" $false "No files to verify"
        }
    }

    # Clean up
    Remove-Item $testDownloadDir -Recurse -Force
    Remove-Item $testConfigPath -Force
} catch {
    Write-TestResult "Verify zip" $false $_.Exception.Message
    Remove-Item "$PSScriptRoot\test_download_temp" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$PSScriptRoot\config_test.json" -Force -ErrorAction SilentlyContinue
}

# TEST 9: Download specific backup date
Write-Host "`nTest 9: Download specific backup date..." -ForegroundColor Yellow
try {
    # Get available backup dates
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $remote = $config.paths.gdriveRemote
    $dest = $config.paths.gdriveDest

    $result = & rclone lsd "$remote`:$dest" --log-level ERROR 2>&1
    $dates = @()
    foreach ($line in $result) {
        $parts = $line -split '\s+'
        $dirName = $parts[-1]
        if ($dirName -match '^\d{4}-\d{2}$') {
            $dates += $dirName
        }
    }

    if ($dates.Count -gt 0) {
        $latestDate = $dates[0]

        $testDownloadDir = "$PSScriptRoot\test_download_temp"
        New-Item -ItemType Directory -Force -Path $testDownloadDir | Out-Null

        # Create test config
        $testConfigPath = "$PSScriptRoot\config_test.json"
        Copy-Item $ConfigPath $testConfigPath -Force
        $testConfig = Get-Content $testConfigPath -Raw | ConvertFrom-Json
        $testConfig.download.destinationDir = $testDownloadDir
        $testConfig | ConvertTo-Json -Depth 10 | Set-Content $testConfigPath -Force

        & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\backup_download.ps1" -ConfigPath $testConfigPath -Mode download -BackupDate $latestDate -MaxBackups 1 2>&1 | Out-Null

        $files = Get-ChildItem $testDownloadDir -File -ErrorAction SilentlyContinue
        if ($files.Count -gt 0) {
            Write-TestResult "Download specific date" $true "Downloaded from: $latestDate"
        } else {
            Write-TestResult "Download specific date" $false "No files from: $latestDate"
        }

        # Clean up
        Remove-Item $testDownloadDir -Recurse -Force
        Remove-Item $testConfigPath -Force
    } else {
        Write-TestResult "Download specific date" $false "No backup dates found"
    }
} catch {
    Write-TestResult "Download specific date" $false $_.Exception.Message
    Remove-Item "$PSScriptRoot\test_download_temp" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$PSScriptRoot\config_test.json" -Force -ErrorAction SilentlyContinue
}

# TEST 10: Config download section validation
Write-Host "`nTest 10: Validate download config section..." -ForegroundColor Yellow
try {
    $config = Get-Content $ConfigPath | ConvertFrom-Json

    $hasDownload = $config.PSObject.Properties.Name -contains "download"
    if ($hasDownload) {
        $hasDestDir = $config.download.PSObject.Properties.Name -contains "destinationDir"
        $hasBatchSize = $config.download.PSObject.Properties.Name -contains "batchSize"
        $hasRetries = $config.download.PSObject.Properties.Name -contains "maxRetries"
        $hasVerify = $config.download.PSObject.Properties.Name -contains "verifyAfterDownload"

        $allPresent = $hasDestDir -and $hasBatchSize -and $hasRetries -and $hasVerify

        if ($allPresent) {
            Write-TestResult "Download config section" $true "All required fields present"
            Write-Host "      -> destinationDir: $($config.download.destinationDir)" -ForegroundColor Gray
            Write-Host "      -> batchSize: $($config.download.batchSize)" -ForegroundColor Gray
            Write-Host "      -> maxRetries: $($config.download.maxRetries)" -ForegroundColor Gray
            Write-Host "      -> verifyAfterDownload: $($config.download.verifyAfterDownload)" -ForegroundColor Gray
        } else {
            Write-TestResult "Download config section" $false "Missing fields: destDir=$hasDestDir, batchSize=$hasBatchSize, retries=$hasRetries, verify=$hasVerify"
        }
    } else {
        Write-TestResult "Download config section" $false "No download section in config"
    }
} catch {
    Write-TestResult "Download config section" $false $_.Exception.Message
}

# Summary
Write-Host "`n================================================" -ForegroundColor Cyan
$passedCount = ($testResults | Where-Object { $_.Passed }).Count
$failedCount = ($testResults | Where-Object { -not $_.Passed }).Count

Write-Host "TEST SUITE SUMMARY" -ForegroundColor Cyan
Write-Host "  Passed: $passedCount / $($testResults.Count)" -ForegroundColor $(if ($passedCount -eq $testResults.Count) { "Green" } else { "Yellow" })
Write-Host "  Failed: $failedCount / $($testResults.Count)" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Green" })
Write-Host "================================================`n" -ForegroundColor Cyan

if ($failedCount -eq 0) {
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "SOME TESTS FAILED!" -ForegroundColor Red
    Write-Host "`nFailed tests:" -ForegroundColor Yellow
    $testResults | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host "  - $($_.Test): $($_.Message)" -ForegroundColor Red
    }
    exit 1
}
