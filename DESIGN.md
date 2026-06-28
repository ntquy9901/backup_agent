# BMAD Backup Agent - Thiết Kế Hệ Thống

## 1. Tổng Quan

### 1.1 Mục tiêu
Hệ thống backup tự động cho các project folders với khả năng:
- Zip và upload lên Google Drive
- Download từ Google Drive về máy khác
- Hỗ trợ xử lý song song (parallel) để tăng tốc độ
- Config-driven, dễ dàng tùy chỉnh

### 1.2 Architecture Overview

```
+-------------------+          +-------------------+          +-------------------+
|   Source Machine  |          |   Google Drive    |          | Dest Machine      |
|                   |          |                   |          |                   |
|  +-------------+  |          |  +-------------+  |          |  +-------------+  |
|  | Backup      |  | Upload   |  |             |  | Download |  | Download    |  |
|  | Script      |--+--------->|  | Cloud       |--+--------->|  | Script      |  |
|  +-------------+  |          |  | Storage     |  |          |  +-------------+  |
|                   |          |  +-------------+  |          |                   |
|  D:\bmad-projects |          |  bmad-backups/   |          |  D:\restored\     |
+-------------------+          +-------------------+          +-------------------+
```

---

## 2. Upload Backup (Source Machine)

### 2.1 Components

```
backup_agent/
├── backup_to_gdrive_v2.ps1    # Main upload script
├── config.json                  # Configuration file
├── temp/                        # Temporary zip storage
└── logs/                        # Operation logs
```

### 2.2 Upload Modes

| Mode | Description | Disk Usage | Speed | Use Case |
|------|-------------|------------|-------|----------|
| **streaming** | Zip→Upload→Delete per folder | 1x folder | Slow | Low disk space |
| **batch** | Zip all→Upload all→Delete all | Nx folders | Fast | High disk space |
| **parallel** | Process batchSize folders simultaneously | BatchSize x folder | **Fastest** | **Recommended** |

### 2.3 Parallel Upload Flow

```
┌─────────────────────────────────────────────────────────────┐
│ PARALLEL UPLOAD MODE (batchSize = 3)                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Batch 1:                                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ Folder A    │  │ Folder B    │  │ Folder C    │        │
│  │ Zip → Upload│  │ Zip → Upload│  │ Zip → Upload│        │
│  │ (parallel)  │  │ (parallel)  │  │ (parallel)  │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │                │
│         └────────────────┴────────────────┘                │
│                     All Done                                │
│                                                              │
│  Batch 2:  [Folder D] [Folder E] [Folder F] → same pattern │
│  ...                                                         │
└─────────────────────────────────────────────────────────────┘
```

### 2.4 Configuration (config.json)

```json
{
  "paths": {
    "sourceDir": "D:\\bmad-projects",          # Source folders
    "tempDir": "D:\\backup_agent\\temp",      # Temp zip storage
    "gdriveRemote": "gdrive",                 # Rclone remote name
    "gdriveDest": "bmad-backups"              # GDrive destination folder
  },
  "mode": {
    "type": "parallel"                         # streaming | batch | parallel
  },
  "upload": {
    "parallelUploads": true,                   # Enable parallel
    "batchSize": 3,                           # Folders per batch
    "maxRetries": 3                           # Retry attempts
  },
  "download": {
    "destinationDir": "D:\\downloads",        # Download destination
    "batchSize": 3,                           # Files per batch
    "verifyAfterDownload": true               # Verify zip integrity
  }
}
```

---

## 3. Download Backup (Destination Machine)

### 3.1 Components

```
backup_agent/
├── backup_download.ps1             # Main download script
├── config.json                      # Shared configuration
├── downloads/                       # Downloaded files
└── download_logs/                   # Download logs
```

### 3.2 Download Modes

| Mode | Description |
|------|-------------|
| **list** | List available backups on GDrive |
| **download** | Download selected backups |
| **verify** | Verify downloaded zip integrity |

### 3.3 Parallel Download Flow

```
┌─────────────────────────────────────────────────────────────┐
│ PARALLEL DOWNLOAD MODE (batchSize = 3)                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  GDrive:                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ file_a.zip  │  │ file_b.zip  │  │ file_c.zip  │        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
│         │                │                │                │
│         ▼                ▼                ▼                │
│  ┌─────────────────────────────────────────────────┐       │
│  │     Download Batch (3 files parallel)           │       │
│  │  ┌──────┐ ┌──────┐ ┌──────┐                    │       │
│  │  │file_a│ │file_b│ │file_c│                    │       │
│  │  │.zip  │ │.zip  │ │.zip  │                    │       │
│  │  └──┬───┘ └──┬───┘ └──┬───┘                    │       │
│  └─────┼────────┼────────┼──────────────────────┘       │
│        ▼        ▼        ▼                               │
│  Local:  D:\downloads\                                   │
│                                                              │
│  Optional: Verify → Extract → Delete zip                  │
└─────────────────────────────────────────────────────────────┘
```

### 3.4 Download Commands

```powershell
# List available backups
.\backup_download.ps1 -Mode list

# Download latest backup
.\backup_download.ps1 -Mode download

# Download specific backup date
.\backup_download.ps1 -Mode download -BackupDate "2025-06"

# Download and extract
.\backup_download.ps1 -Mode download -Extract

# Download limited files (for testing)
.\backup_download.ps1 -Mode download -MaxBackups 5

# Verify downloaded files
.\backup_download.ps1 -Mode verify
```

---

## 4. Google Drive Structure

```
gdrive:bmad-backups/
├── 2025-06/                          # Year-Month folder
│   ├── bmad-adaptive-learning_20250628_143022.zip
│   ├── bmad-agents_projects_code_review_20250628_143045.zip
│   ├── bmad-ai-agent-code-review_20250628_143102.zip
│   ├── MANIFEST_20250628_143022.txt   # Backup summary
│   └── backup_20250628_143022.log     # Detailed log
│
├── 2025-07/
│   └── ...
```

**Manifest Format:**
```
=== BMAD BACKUP MANIFEST ===
Timestamp: 20250628_14:30:22
Source: D:\bmad-projects
Destination: gdrive:bmad-backups/2025-06
Total Folders: 28

[OK] adaptive-learning | SUCCESS | Zip: 6.27 MB
[OK] agents_projects_code_review | SUCCESS | Zip: 161.2 MB
...
```

---

## 5. Error Handling & Recovery

### 5.1 Upload Errors

| Error | Action |
|-------|--------|
| Not enough disk space | Skip folder (config: `failAction: skip`) |
| Zip failed | Log error, continue next folder |
| Upload failed | Retry up to maxRetries (default: 3) |
| rclone not found | Exit with error, install rclone |

### 5.2 Download Errors

| Error | Action |
|-------|--------|
| Backup not found | List available, exit with error |
| Download failed | Retry up to maxRetries |
| Zip corrupted | Log error, keep file for manual check |
| Verify failed | Mark as failed, continue others |

### 5.3 Logging

All operations logged to:
- Console output (real-time)
- Log file: `temp/backup_YYYYMMDD_HHmmss.log`
- Manifest: `temp/MANIFEST_YYYYMMDD_HHmmss.txt`

---

## 6. Security Considerations

### 6.1 Credentials

- rclone config stored in: `%USERPROFILE%\AppData\Roaming\rclone\rclone.conf`
- Token encrypted with OAuth2
- **DO NOT** commit rclone.conf to version control

### 6.2 Data Privacy

- All data transferred via HTTPS (rclone → Google Drive)
- Local zip files deleted after upload (if `deleteLocalZip: true`)
- Logs may contain file names but not content

---

## 7. Performance Estimates

### 7.1 Upload Performance (28 folders, ~5.7 GB)

| Mode | Estimated Time | Disk Peak |
|------|----------------|------------|
| streaming | ~15-20 min | ~200 MB |
| parallel (batch=3) | ~8-10 min | ~600 MB |
| batch | ~5-8 min | ~5.7 GB |

### 7.2 Download Performance

| Size | Connection | Estimated Time |
|------|------------|-----------------|
| 1 GB | 100 Mbps | ~1.5 min |
| 5 GB | 100 Mbps | ~7 min |
| 5 GB | Parallel (3) | ~3-4 min |

---

## 8. Deployment Checklist

### Source Machine (Upload)

- [ ] Install rclone: `winget install rclone.rclone`
- [ ] Install 7-Zip (optional): `winget install 7zip.7zip`
- [ ] Configure rclone: `rclone config` (login to Google Drive)
- [ ] Copy `backup_agent/` folder to source machine
- [ ] Edit `config.json` with correct paths
- [ ] Run tests: `.\run_tests.bat`
- [ ] Test backup: `.\backup_to_gdrive_v2.ps1` (test mode first)

### Destination Machine (Download)

- [ ] Install rclone
- [ ] Install 7-Zip (optional)
- [ ] Copy `backup_agent/` folder to destination machine
- [ ] Copy `rclone.conf` from source machine OR re-run `rclone config`
- [ ] Edit `config.json` with correct download destination
- [ ] Test list: `.\backup_download.ps1 -Mode list`
- [ ] Test download: `.\backup_download.ps1 -Mode download -MaxBackups 1`

---

## 9. Troubleshooting

### Issue: "rclone not found"
**Fix:** Install rclone and restart terminal

### Issue: "Remote not found"
**Fix:** Run `rclone config` to set up Google Drive

### Issue: "Upload timeout"
**Fix:** Increase `maxRetries` in config.json

### Issue: "Not enough disk space"
**Fix:** Increase `minFreeSpaceMB` OR reduce `batchSize` OR use `streaming` mode

### Issue: "Download verification failed"
**Fix:** Check internet connection, re-download file

---

## 10. Future Enhancements

- [ ] Encryption (zip password before upload)
- [ ] Incremental backup (only changed files)
- [ ] Scheduling (Windows Task Scheduler integration)
- [ ] Notifications (email/Slack on completion)
- [ ] Multi-destination support (GDrive + Dropbox + S3)
- [ ] Web UI for easy management
