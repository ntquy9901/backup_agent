@echo off
REM ============================================================
REM BMAD Backup Download - Quick Launcher
REM ============================================================

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"

echo.
echo ========================================
echo   BMAD BACKUP DOWNLOAD
echo ========================================
echo.
echo Choose action:
echo   1. List available backups
echo   2. Download latest backup
echo   3. Download specific backup
echo   4. Verify downloaded files
echo.
set /p choice="Select (1-4): "

if "%choice%"=="1" (
    echo.
    echo Listing available backups...
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%backup_download.ps1" -Mode list
) else if "%choice%"=="2" (
    echo.
    echo Downloading latest backup...
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%backup_download.ps1" -Mode download
) else if "%choice%"=="3" (
    echo.
    set /p backupDate="Enter backup date (YYYY-MM): "
    echo.
    echo Downloading backup: %backupDate%
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%backup_download.ps1" -Mode download -BackupDate "%backupDate%"
) else if "%choice%"=="4" (
    echo.
    echo Verifying downloaded files...
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%backup_download.ps1" -Mode verify
) else (
    echo Invalid choice.
    pause
    exit /b 1
)

echo.
echo Done.
pause
