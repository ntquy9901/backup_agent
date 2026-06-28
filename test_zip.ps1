# ============================================================
# TEST: Zip Functionality
# ============================================================

$ErrorActionPreference = "Stop"
$testDir = "$env:TEMP\bmad_zip_test_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$testZip = "$env:TEMP\bmad_zip_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"

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
Write-Host "TEST: Zip Functionality" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

$allPassed = $true

# Cleanup on exit
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -SupportEvent -Action {
    if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
    if (Test-Path $testZip) { Remove-Item $testZip -Force }
}

# TEST 1: Check 7-Zip installed
Write-Host "Test 1: Check 7-Zip installed..." -ForegroundColor Yellow
try {
    if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
        $version = & 7z.exe 2>&1 | Select-String "7-Zip"
        Write-TestResult "7-Zip installed" $true $version
    } else {
        Write-TestResult "7-Zip installed" $false "Not found, will use PowerShell Compress-Archive (slower)"
        # This is a warning, not a failure
    }
} catch {
    Write-TestResult "7-Zip installed" $false "Error checking: $_"
}

# TEST 2: Create test folder structure
Write-Host "`nTest 2: Create test folder..." -ForegroundColor Yellow
try {
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    New-Item -ItemType Directory -Path "$testDir\subfolder" -Force | Out-Null

    Set-Content -Path "$testDir\file1.txt" -Value "Test file 1 - $(Get-Date)"
    Set-Content -Path "$testDir\file2.txt" -Value "Test file 2 - $(Get-Date)"
    Set-Content -Path "$testDir\subfolder\file3.txt" -Value "Test file 3 - $(Get-Date)"

    $fileCount = (Get-ChildItem $testDir -Recurse -File).Count
    Write-TestResult "Create test folder" $true "Created $fileCount test files"
} catch {
    Write-TestResult "Create test folder" $false $_.Exception.Message
    $allPassed = $false
}

# TEST 3: Zip with 7-Zip
Write-Host "`nTest 3: Zip with 7-Zip..." -ForegroundColor Yellow
$use7zip = $false
try {
    if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
        & 7z.exe a -tzip $testZip $testDir -mx5 -bso0 -bsp0 > $null 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path $testZip)) {
            $zipSize = [math]::Round((Get-Item $testZip).Length / 1KB, 2)
            Write-TestResult "Zip with 7-Zip" $true "Zip created: $zipSize KB"
            $use7zip = $true
        } else {
            Write-TestResult "Zip with 7-Zip" $false "Exit code: $LASTEXITCODE"
            $allPassed = $false
        }
    } else {
        Write-TestResult "Zip with 7-Zip" $false "7-Zip not available, skipping test"
    }
} catch {
    Write-TestResult "Zip with 7-Zip" $false $_.Exception.Message
}

# TEST 4: Zip with PowerShell (fallback)
Write-Host "`nTest 4: Zip with PowerShell Compress-Archive..." -ForegroundColor Yellow
try {
    if (Test-Path $testZip) { Remove-Item $testZip -Force }
    Compress-Archive -Path $testDir -DestinationPath $testZip -Force

    if (Test-Path $testZip) {
        $zipSize = [math]::Round((Get-Item $testZip).Length / 1KB, 2)
        Write-TestResult "Zip with PowerShell" $true "Zip created: $zipSize KB"
    } else {
        Write-TestResult "Zip with PowerShell" $false "Zip file not created"
        $allPassed = $false
    }
} catch {
    Write-TestResult "Zip with PowerShell" $false $_.Exception.Message
    $allPassed = $false
}

# TEST 5: Verify zip integrity
Write-Host "`nTest 5: Verify zip integrity..." -ForegroundColor Yellow
try {
    if ($use7zip) {
        $result = & 7z.exe t $testZip -bso0 -bsp0 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-TestResult "Zip integrity (7-Zip)" $true "Archive is valid"
        } else {
            Write-TestResult "Zip integrity (7-Zip)" $false "Exit code: $LASTEXITCODE"
            $allPassed = $false
        }
    } else {
        $extractTest = "$env:TEMP\bmad_extract_test"
        New-Item -ItemType Directory -Path $extractTest -Force | Out-Null
        Expand-Archive -Path $testZip -DestinationPath $extractTest -Force
        $extractedCount = (Get-ChildItem $extractTest -Recurse -File).Count
        Remove-Item $extractTest -Recurse -Force

        if ($extractedCount -ge 3) {
            Write-TestResult "Zip integrity (PowerShell)" $true "Extracted $extractedCount files successfully"
        } else {
            Write-TestResult "Zip integrity (PowerShell)" $false "Only extracted $extractedCount files (expected 3+)"
            $allPassed = $false
        }
    }
} catch {
    Write-TestResult "Zip integrity" $false $_.Exception.Message
    $allPassed = $false
}

# TEST 6: Delete zip
Write-Host "`nTest 6: Delete zip file..." -ForegroundColor Yellow
try {
    if (Test-Path $testZip) {
        Remove-Item $testZip -Force
        if (-not (Test-Path $testZip)) {
            Write-TestResult "Delete zip file" $true "Zip file deleted successfully"
        } else {
            Write-TestResult "Delete zip file" $false "File still exists"
            $allPassed = $false
        }
    } else {
        Write-TestResult "Delete zip file" $true "No zip file to delete (already cleaned)"
    }
} catch {
    Write-TestResult "Delete zip file" $false $_.Exception.Message
    $allPassed = $false
}

# TEST 7: Test actual folder from bmad-projects
Write-Host "`nTest 7: Test zip a real bmad-projects folder..." -ForegroundColor Yellow
try {
    $bmadProjectsDir = "D:\bmad-projects"
    if (Test-Path $bmadProjectsDir) {
        $smallFolder = Get-ChildItem $bmadProjectsDir -Directory |
                       Where-Object { $_.Name -notin @(".claude", "_bmad", "_bmad-output", "backup_agent") } |
                       Sort-Object { (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } |
                       Select-Object -First 1

        if ($smallFolder) {
            $realTestZip = "$env:TEMP\bmad_real_test_$($smallFolder.Name).zip"

            if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
                & 7z.exe a -tzip $realTestZip $smallFolder.FullName -mx5 -bso0 -bsp0 > $null 2>&1
            } else {
                Compress-Archive -Path $smallFolder.FullName -DestinationPath $realTestZip -Force
            }

            if (Test-Path $realTestZip) {
                $zipSize = [math]::Round((Get-Item $realTestZip).Length / 1MB, 2)
                Write-TestResult "Zip real folder" $true "$($smallFolder.Name) -> $zipSize MB"
                Remove-Item $realTestZip -Force
            } else {
                Write-TestResult "Zip real folder" $false "Failed to create zip"
                $allPassed = $false
            }
        } else {
            Write-TestResult "Zip real folder" $false "No suitable folder found for testing"
        }
    } else {
        Write-TestResult "Zip real folder" $false "bmad-projects directory not found"
    }
} catch {
    Write-TestResult "Zip real folder" $false $_.Exception.Message
}

# Cleanup
if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
if (Test-Path $testZip) { Remove-Item $testZip -Force }

# Summary
Write-Host "`n================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
    Write-Host "Zip functionality is working correctly!" -ForegroundColor Green
} else {
    Write-Host "SOME TESTS FAILED" -ForegroundColor Red
}
Write-Host "================================================`n" -ForegroundColor Cyan

exit $(if ($allPassed) { 0 } else { 1 })
