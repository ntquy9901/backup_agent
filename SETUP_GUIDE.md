# BMAD Backup Setup Guide

## Quick Start - Install Required Tools

### Step 1: Install rclone (for Google Drive upload)
```powershell
winget install rclone.rclone
```

### Step 2: Install 7-Zip (optional - faster compression)
```powershell
winget install 7zip.7zip
```
If you skip 7-Zip, the script will use PowerShell's Compress-Archive (slower but works).

---

## Configure Google Drive Access

### Run rclone config:
```bash
rclone config
```

Follow the prompts:
```
Current remotes:

Name                 Type
====                 ====
Edit remote
n) New remote
d) Delete remote
r) Rename remote
c) Copy remote
s) Set configuration password
q) Quit config
e/n/d/r/c/s/q> n

name> gdrive

Option type.
Choose a number from below, or type in your own value
 1 / 1Fichier
 2 / Alias for an existing remote
...
17 / Google Drive
...
type> 17

Option scopes.
Choose a number from below, or type in your own value
 1 / Full access to all files, excluding Application Data Folder.
...
scope> 1

Option root_folder_id.
Choose a number from below, or type in your own value
root_folder_id>

Option service_account_file.
Choose a number from below, or type in your own value
service_account_file>

Edit advanced config? (y/n)
y/n> n

Use auto config? (y/n)
y/n> y

# Browser will open - login to ntquy99@gmail.com
# Grant permissions to rclone

Choose a number from below, or type in an own value
 1 / OneDrive
...
17 / Google Drive
...
type> 17

Confirm this is correct (y/n)
y/n> y

Current remotes:

Name                 Type
====                 ====
gdrive              drive

e/n/d/r/c/s/q> q
```

---

## Test rclone connection:
```bash
rclone ls gdrive:
```

You should see your Google Drive files listed.

---

## Run Backup

### Option 1: Quick (double-click)
Run: `D:\bmad-projects\backup_agent\run_backup.bat`

### Option 2: PowerShell
```powershell
cd D:\bmad-projects\backup_agent
.\backup_to_gdrive.ps1
```

### Option 3: Custom parameters
```powershell
.\backup_to_gdrive.ps1 -SourceDir "D:\bmad-projects" -GdriveDest "gdrive:bmad-backups"
```

---

## What the script does (Streaming Mode)

```
For each folder in D:\bmad-projects:
    1. Create ZIP with timestamp (bmad-foldername_20250628_143022.zip)
    2. Upload ZIP to Google Drive (gdrive:bmad-backups/2025-06/)
    3. Delete ZIP from local disk (save space!)
    4. Log result (success/fail)
    5. Continue to next folder

Result:
    - No disk space buildup
    - If script stops, resume easily
    - Detailed log of everything
```

---

## Google Drive Structure After Backup

```
gdrive:bmad-backups/
└── 2025-06/
    ├── bmad-adaptive-learning_20250628_143022.zip
    ├── bmad-agents_projects_code_review_20250628_143045.zip
    ├── bmad-ai-agent-code-review_20250628_143102.zip
    ├── ...
    ├── MANIFEST_20250628_143022.txt    (backup summary)
    └── backup_20250628_143022.log      (detailed log)
```

---

## Troubleshooting

### Issue: "rclone not found"
**Fix:** Install rclone and restart PowerShell:
```powershell
winget install rclone.rclone
# Close and reopen PowerShell
```

### Issue: Upload fails intermittently
**Fix:** Script auto-retries 3 times per folder. If still failing:
- Check internet connection
- Verify Google Drive quota
- Check rclone log in temp folder

### Issue: "Script cannot run because execution policy is..."
**Fix:** Run from batch file or use:
```powershell
powershell -ExecutionPolicy Bypass -File backup_to_gdrive.ps1
```

---

## Advanced: Schedule Automatic Backup

Create a Windows Task Scheduler task:
```powershell
$action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File D:\bmad-projects\backup_agent\backup_to_gdrive.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At "02:00AM"
Register-ScheduledTask -TaskName "BMAD-Backup" -Action $action -Trigger $trigger -Description "Daily backup of bmad-projects to Google Drive"
```

---

## Files Created

| File | Purpose |
|------|---------|
| `backup_to_gdrive.ps1` | Main backup script (streaming mode) |
| `run_backup.bat` | Quick launcher |
| `temp/` | Temporary zips (cleaned up automatically) |
| `temp/backup_*.log` | Detailed operation logs |
| `temp/MANIFEST_*.txt` | Backup summary |
