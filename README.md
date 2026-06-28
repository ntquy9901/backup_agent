# BMAD Backup Agent - Testing & Deployment Guide

Complete backup solution with **config-driven testing** and **progressive deployment**.

---

## 📁 File Structure

```
D:\bmad-projects\backup_agent\
├── config.json                    # ← Configuration file (edit this!)
├── backup_to_gdrive_v2.ps1        # ← Main script (uses config)
├── run_backup.bat                 # ← Quick launcher
├── run_tests.bat                  # ← Run all tests
│
├── test_gdrive.ps1                # ← Test 1: GDrive connection
├── test_zip.ps1                   # ← Test 2: Zip functionality
├── test_single_backup.ps1         # ← Test 3: End-to-end (1 folder)
│
└── SETUP_GUIDE.md                 # ← Setup instructions
```

---

## 🧪 Testing Strategy

### Phase 1: Component Tests (Run individually)

```powershell
# Test 1: Google Drive connection
.\test_gdrive.ps1

# Test 2: Zip functionality
.\test_zip.ps1

# Test 3: Single folder backup (end-to-end)
.\test_single_backup.ps1
```

### Phase 2: Full Test Suite

```batch
# Run all tests
run_tests.bat
```

Output:
```
[1/3] Testing Google Drive connection...
  Result: PASS

[2/3] Testing Zip functionality...
  Result: PASS

[3/3] Testing single folder backup...
  Result: PASS

========================================
  TEST SUITE SUMMARY
========================================
  Passed: 3 / 3
  Failed: 0 / 3
========================================
```

### Phase 3: Test Mode (Limited Folders)

Edit `config.json`:
```json
"test": {
  "enabled": true,
  "testFolder": "backup_agent",
  "maxFoldersToProcess": 1
}
```

Run:
```powershell
.\backup_to_gdrive_v2.ps1
```

This will backup only 1 folder for verification.

---

## ⚙️ Configuration Options

Edit `config.json` to customize behavior:

### Enable/Disable Steps
```json
"steps": {
  "checkDiskSpace": true,     // Check space before each zip
  "zipFolders": true,         // Create zip files
  "uploadToGdrive": true,     // Upload to Google Drive
  "deleteLocalZip": true,     // Delete zip after upload (saves disk!)
  "uploadManifest": true      // Upload manifest file
}
```

### Backup Mode
```json
"mode": {
  "type": "parallel"
  // "streaming" = zip→upload→delete per folder (saves disk space)
  // "batch"     = zip all→upload all→delete all (faster but needs more space)
  // "parallel"  = process multiple folders simultaneously (best speed!)
}
```

**Mode Comparison:**

| Mode | Speed | Disk Usage | Best For |
|------|-------|------------|----------|
| **streaming** | Slow | Minimal (1x folder size) | Low disk space |
| **batch** | Fast | High (all folders zipped) | Plenty of disk space |
| **parallel** | **Fastest** | Moderate (batchSize x folder) | **Best balance** |

**Parallel Mode Example (batchSize = 3):**
```
Batch 1: [Folder A] [Folder B] [Folder C] → zip → upload (all at once)
Batch 2: [Folder D] [Folder E] [Folder F] → zip → upload (all at once)
...
```

### Space Check Settings
```json
"spaceCheck": {
  "marginMultiplier": 1.5,     // Need 1.5x folder size
  "minFreeSpaceMB": 500,      // + 500MB buffer
  "failAction": "skip"        // "skip" = continue, "stop" = abort
}
```

### Parallel Upload Settings
```json
"upload": {
  "parallelUploads": true,
  "batchSize": 3,
  "transfers": 4,
  "comment": "parallelUploads = enable parallel mode | batchSize = folders processed simultaneously | transfers = rclone internal concurrent uploads"
}
```

### Paths (Reusability)
```json
"paths": {
  "sourceDir": "D:\\bmad-projects",
  "tempDir": "D:\\bmad-projects\\backup_agent\\temp",
  "gdriveRemote": "gdrive",
  "gdriveDest": "bmad-backups"
}
```

**To backup different folders**, create a new config file:
```json
// config_other.json
{
  "paths": {
    "sourceDir": "E:\\my-other-projects",
    ...
  }
}
```

Then run:
```powershell
.\backup_to_gdrive_v2.ps1 -ConfigPath .\config_other.json
```

---

## 🚀 Deployment Steps

### Step 1: Install Dependencies
```powershell
winget install rclone.rclone
winget install 7zip.7zip
```

### Step 2: Configure Google Drive
```bash
rclone config
# Name: gdrive
# Type: drive
# Login with ntquy99@gmail.com
```

### Step 3: Run Tests
```batch
run_tests.bat
```

### Step 4: Test Mode (1 folder)
Edit `config.json` → Set `"enabled": true` in `"test"` section
```powershell
.\backup_to_gdrive_v2.ps1
```

### Step 5: Production Mode
Edit `config.json` → Set `"enabled": false` in `"test"` section
```powershell
.\backup_to_gdrive_v2.ps1
```

Or use the quick launcher:
```batch
run_backup.bat
```

---

## 📊 Test Results Interpretation

| Test | PASS Meaning | FAIL Meaning |
|------|--------------|--------------|
| **test_gdrive** | GDrive connected, can upload/delete | Config error or auth issue |
| **test_zip** | 7-Zip or PowerShell working | Install 7-Zip or check permissions |
| **test_single_backup** | Full pipeline working | Check above tests first |

---

## 🔧 Common Configurations

### Config 1: Max Space Saving (Streaming)
```json
{
  "mode": { "type": "streaming" },
  "steps": {
    "checkDiskSpace": true,
    "deleteLocalZip": true
  }
}
```
→ Best when disk space is limited

### Config 2: Fastest Speed (Batch)
```json
{
  "mode": { "type": "batch" },
  "steps": {
    "checkDiskSpace": false,
    "deleteLocalZip": true
  }
}
```
→ Best when you have plenty of disk space

### Config 3: Zip Only (No Upload)
```json
{
  "steps": {
    "zipFolders": true,
    "uploadToGdrive": false,
    "deleteLocalZip": false
  }
}
```
→ For local backup only

### Config 4: Test Single Folder
```json
{
  "test": { "enabled": true, "maxFoldersToProcess": 1 }
}
```
→ Quick verification before full run

---

## 📝 Log Files

After each run, find detailed logs in:
```
D:\bmad-projects\backup_agent\temp\
├── backup_20250628_143022.log     ← Detailed operation log
└── MANIFEST_20250628_143022.txt    ← Backup summary
```

---

## 🆘 Troubleshooting

### Issue: "rclone not found"
```powershell
winget install rclone.rclone
# Restart PowerShell
```

### Issue: GDrive upload fails
```powershell
# Test connection
.\test_gdrive.ps1

# Reconfigure if needed
rclone config
```

### Issue: "Not enough disk space"
```json
// Reduce space requirements in config.json
"spaceCheck": {
  "marginMultiplier": 1.2,
  "minFreeSpaceMB": 200
}
```

### Issue: Zip fails
```powershell
# Test zip
.\test_zip.ps1

# Install 7-Zip if needed
winget install 7zip.7zip
```
