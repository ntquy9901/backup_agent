@echo off
REM ============================================================
REM BMAD Backup Test Suite
REM ============================================================

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "PASS=0"
set "FAIL=0"

echo.
echo ========================================
echo   BMAD BACKUP TEST SUITE
echo ========================================
echo.

REM Test 1: Google Drive Connection
echo [1/3] Testing Google Drive connection...
echo ----------------------------------------
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%test_gdrive.ps1"
if !errorlevel! equ 0 (
    set /a PASS+=1
    echo   Result: PASS
) else (
    set /a FAIL+=1
    echo   Result: FAIL
)
echo.

REM Test 2: Zip Functionality
echo [2/3] Testing Zip functionality...
echo ----------------------------------------
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%test_zip.ps1"
if !errorlevel! equ 0 (
    set /a PASS+=1
    echo   Result: PASS
) else (
    set /a FAIL+=1
    echo   Result: FAIL
)
echo.

REM Test 3: Single Folder Backup (End-to-End)
echo [3/3] Testing single folder backup...
echo ----------------------------------------
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%test_single_backup.ps1"
if !errorlevel! equ 0 (
    set /a PASS+=1
    echo   Result: PASS
) else (
    set /a FAIL+=1
    echo   Result: FAIL
)
echo.

REM Summary
echo ========================================
echo   TEST SUITE SUMMARY
echo ========================================
echo   Passed: !PASS! / 3
echo   Failed: !FAIL! / 3
echo ========================================
echo.

if !FAIL! equ 0 (
    echo [SUCCESS] All tests passed! Ready for full backup.
    exit /b 0
) else (
    echo [FAILURE] Some tests failed. Please fix before running full backup.
    exit /b 1
)

pause
