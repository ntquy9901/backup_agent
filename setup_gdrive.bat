@echo off
REM ============================================================
REM Setup Google Drive for Rclone
REM ============================================================

echo.
echo ========================================
echo   GOOGLE DRIVE SETUP FOR RCLONE
echo ========================================
echo.
echo This will open a browser for you to login to Google Drive.
echo Please have your ntquy99@gmail.com account ready.
echo.
echo CONFIGURATION STEPS:
echo.
echo 1. Remote name: gdrive
echo 2. Storage type: 17 (Google Drive)
echo 3. Scope: 1 (Full access - all files)
echo 4. Root folder ID: 1Ru5ZYG-gGejfd6M_Y68wKUq-V46mt3Er
echo    (This is your public backup folder)
echo 5. Service account: n (No)
echo 6. Advanced config: n (No)
echo 7. Auto config: y (Yes - opens browser)
echo 8. Login with ntquy99@gmail.com
echo 9. Confirm: y (Yes)
echo.
echo ========================================
echo.

rclone config

echo.
echo ========================================
echo   SETUP COMPLETE
echo ========================================
echo.
echo Testing connection...
rclone ls gdrive: --max-depth 1
echo.
echo If you see files listed above, setup was successful!
echo.
pause
