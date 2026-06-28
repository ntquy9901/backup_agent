# BMAD Backup Agent - Claude Context

## Project Overview

BMAD Backup Agent là công cụ tự động sao lưu dự án lên Google Drive với khả năng:
- Nén ZIP từng folder và upload song song (parallel mode)
- Tự động xóa file tạm sau khi upload
- Download backup từ Google Drive về máy khác
- Config-driven architecture

## Architecture

```
Source Machine (Upload)           Google Drive              Dest Machine (Download)
+-------------------+             +----------------+         +-------------------+
| backup_to_gdrive  | --> rclone | bmad-backups/  | <-- rclone | backup_download   |
| _v2.ps1           |             | wfp-backups/   |             |   .ps1            |
+-------------------+             | b100-backups/  |             +-------------------+
                                   | iphonevo-...   |
                                   +----------------+
```

## Key Files

| File | Mô tả |
|------|-------|
| `backup_to_gdrive_v2.ps1` | Script upload backup chính |
| `backup_download.ps1` | Script download backup |
| `config.json` | Config mặc định cho bmad-projects |
| `config_wfp.json` | Config cho WFP_Project |
| `config_b100.json` | Config cho B100_project |
| `config_iphonevo.json` | Config cho iphonevo |
| `run_backup.bat` | Quick launcher cho upload |
| `run_download.bat` | Quick launcher cho download |
| `DESIGN.md` | Tài liệu thiết kế chi tiết |
| `USERGUIDE.md` | Hướng dẫn sử dụng tiếng Việt |

## Configuration Structure

```json
{
  "paths": {
    "sourceDir": "D:\\bmad-projects",      // Source folder cần backup
    "tempDir": "D:\\backup_agent\\temp",   // Folder tạm cho ZIP
    "gdriveRemote": "gdrive",              // Tên rclone remote
    "gdriveDest": "bmad-backups"           // Folder đích trên GDrive
  },
  "mode": {
    "type": "parallel"                     // streaming | batch | parallel
  },
  "upload": {
    "batchSize": 3                         // Số folder xử lý song song
  },
  "folders": {
    "skipList": [".claude", "node_modules"] // Folders bỏ qua
  }
}
```

## Backup Modes

| Mode | Mô tả | Tốc độ | Dùng đĩa |
|------|-------|---------|----------|
| streaming | Zip→Upload→Delete từng folder | Chậm | Ít nhất |
| batch | Zip tất cả→Upload tất cả | Nhanh | Nhiều |
| parallel | Xử lý batchSize folders song song | **Nhanh nhất** | Vừa |

## Rclone Setup

```bash
# Cài đặt
winget install rclone.rclone

# Config Google Drive
rclone config
# -> New remote: gdrive
# -> Type: drive
# -> OAuth2 auth

# Test kết nối
rclone about gdrive:
```

## Usage Examples

```powershell
# Upload backup
.\backup_to_gdrive_v2.ps1
.\backup_to_gdrive_v2.ps1 -ConfigPath config_wfp.json

# Download backup
.\backup_download.ps1 -Mode list
.\backup_download.ps1 -Mode download
.\backup_download.ps1 -Mode download -BackupDate "2026-06"
```

## Deployed Projects

| Project | Source | GDrive Destination |
|---------|--------|-------------------|
| bmad-projects | D:\bmad-projects | gdrive:bmad-backups/2026-06 |
| WFP_Project | D:\WFP_Project | gdrive:wfp-backups/2026-06 |
| B100_project | D:\B100_project | gdrive:b100-backups/2026-06 |
| iphonevo | D:\iphonevo | gdrive:iphonevo-backups/2026-06 |

## Dependencies

- **rclone** - Google Drive upload/download
- **7-Zip** (optional) - Nén ZIP nhanh hơn PowerShell
- **PowerShell 5.1+**

## Error Handling

- Zip failed: Skip folder, continue
- Upload failed: Retry up to maxRetries (default: 3)
- Disk space full: Skip if failAction: skip

## Maintenance

- Logs: `temp/backup_YYYYMMDD_HHmmss.log`
- Temp ZIPs: Tự xóa sau upload (nếu deleteLocalZip: true)
- Old backups: Trên GDrive, giữ theo tháng (YYYY-MM)

## Notes

- Timestamps trong filename: `project_YYYYMMDD_HHmmss.zip`
- Manifest file: `MANIFEST_YYYYMMDD_HHmmss.txt`
- Test mode: Set `test.enabled: true` in config
