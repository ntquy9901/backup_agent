@echo off
REM ============================================================
REM BMAD-PROJECTS BACKUP - Quick Launcher
REM ============================================================

echo.
echo ========================================
echo   BMAD PROJECTS BACKUP TO GOOGLE DRIVE
echo ========================================
echo.

REM Check if rclone is installed
where rclone >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] rclone not found!
    echo [!] Install: winget install rclone.rclone
    echo.
    pause
    exit /b 1
)

REM Run PowerShell script
powershell -ExecutionPolicy Bypass -File "%~dp0backup_to_gdrive.ps1"

echo.
echo Backup process completed. Check log file for details.
pause
