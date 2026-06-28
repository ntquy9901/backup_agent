# ============================================================
# TEST: Google Drive Connection & Upload
# ============================================================

param(
    [string]$Remote = "gdrive",
    [string]$TestFolder = "bmad-backup-test"
)

$ErrorActionPreference = "Stop"

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
Write-Host "TEST: Google Drive Connection & Upload" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

$allPassed = $true

# TEST 1: Check rclone installed
Write-Host "Test 1: Check rclone is installed..." -ForegroundColor Yellow
try {
    $rclonePath = where.exe rclone 2>$null
    if ($rclonePath) {
        $version = & rclone version 2>&1 | Select-String "rclone"
        Write-TestResult "rclone installed" $true $version
    } else {
        Write-TestResult "rclone installed" $false "rclone not found in PATH"
        $allPassed = $false
    }
} catch {
    Write-TestResult "rclone installed" $false $_.Exception.Message
    $allPassed = $false
}

# TEST 2: Check remote configured
Write-Host "`nTest 2: Check remote '$Remote' configured..." -ForegroundColor Yellow
try {
    $remotes = & rclone listremotes 2>&1
    if ($remotes -match "^$Remote`:") {
        Write-TestResult "Remote '$Remote' exists" $true "Found in rclone config"
    } else {
        Write-TestResult "Remote '$Remote' exists" $false "Remote not found. Run: rclone config"
        $allPassed = $false
    }
} catch {
    Write-TestResult "Remote '$Remote' exists" $false $_.Exception.Message
    $allPassed = $false
}

# TEST 3: Test connection (list root)
Write-Host "`nTest 3: Test connection to Google Drive..." -ForegroundColor Yellow
try {
    $result = & rclone ls "$Remote`:" --max-depth 1 2>&1 | Select-Object -First 5
    if ($LASTEXITCODE -eq 0) {
        Write-TestResult "Connection successful" $true "Can list files"
    } else {
        Write-TestResult "Connection successful" $false "Exit code: $LASTEXITCODE"
        $allPassed = $false
    }
} catch {
    Write-TestResult "Connection successful" $false $_.Exception.Message
    $allPassed = $false
}

# TEST 4: Create test file and upload
Write-Host "`nTest 4: Upload test file..." -ForegroundColor Yellow
$testFile = "$env:TEMP\bmad_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$testContent = "BMAD Backup Test - $(Get-Date -Format 'yyyy-MM-dd HH-mm-ss')"
try {
    Set-Content -Path $testFile -Value $testContent
    $remotePath = "$Remote`:$TestFolder/test_upload.txt"
    & rclone copyto $testFile $remotePath --log-level ERROR 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-TestResult "Upload test file" $true "File uploaded to $remotePath"
    } else {
        Write-TestResult "Upload test file" $false "Exit code: $LASTEXITCODE"
        $allPassed = $false
    }
} catch {
    Write-TestResult "Upload test file" $false $_.Exception.Message
    $allPassed = $false
}

# TEST 5: Verify uploaded file exists
Write-Host "`nTest 5: Verify uploaded file exists..." -ForegroundColor Yellow
try {
    $result = & rclone ls "$Remote`:$TestFolder/test_upload.txt" 2>&1
    if ($LASTEXITCODE -eq 0 -and $result) {
        Write-TestResult "File verification" $true "File exists on Google Drive"
    } else {
        Write-TestResult "File verification" $false "File not found after upload"
        $allPassed = $false
    }
} catch {
    Write-TestResult "File verification" $false $_.Exception.Message
    $allPassed = $false
}

# TEST 6: Delete test file
Write-Host "`nTest 6: Delete test file..." -ForegroundColor Yellow
try {
    & rclone delete "$Remote`:$TestFolder" --log-level ERROR 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-TestResult "Delete test file" $true "Test folder cleaned up"
    } else {
        Write-TestResult "Delete test file" $false "Exit code: $LASTEXITCODE"
        $allPassed = $false
    }
} catch {
    Write-TestResult "Delete test file" $false $_.Exception.Message
    $allPassed = $false
}

# Clean up local test file
if (Test-Path $testFile) {
    Remove-Item $testFile -Force
}

# TEST 7: Verify deletion
Write-Host "`nTest 7: Verify test file deleted..." -ForegroundColor Yellow
try {
    $result = & rclone ls "$Remote`:$TestFolder" 2>&1
    if (-not $result -or $LASTEXITCODE -ne 0) {
        Write-TestResult "Delete verification" $true "Test folder removed"
    } else {
        Write-TestResult "Delete verification" $false "Folder still exists"
        $allPassed = $false
    }
} catch {
    Write-TestResult "Delete verification" $false $_.Exception.Message
    $allPassed = $false
}

# Summary
Write-Host "`n================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
    Write-Host "Google Drive is ready for backup!" -ForegroundColor Green
} else {
    Write-Host "SOME TESTS FAILED" -ForegroundColor Red
    Write-Host "Please fix the issues before running backup." -ForegroundColor Red
}
Write-Host "================================================`n" -ForegroundColor Cyan

exit $(if ($allPassed) { 0 } else { 1 })
