# BMAD Backup Agent - Hướng Dẫn Sử Dụng

## Mục Lục

1. [Giới thiệu](#1-giới-thiệu)
2. [Cài đặt](#2-cài-đặt)
3. [Cấu hình Google Drive](#3-cấu-hình-google-drive)
4. [Sao lưu (Upload)](#4-sao-lưu-upload)
5. [Khôi phục (Download)](#5-khôi-phục-download)
6. [File cấu hình](#6-file-cấu-hình)
7. [Xử lý sự cố](#7-xử-lý-sự-cố)

---

## 1. Giới thiệu

BMAD Backup Agent là công cụ tự động sao lưu các folder trong `D:\bmad-projects` lên Google Drive, cho phép khôi phục lại trên máy khác.

### Tính năng chính

- **NénZIP** folder trước khi upload
- **Upload song song** (parallel) để tăng tốc độ
- **Tự động xóa** file ZIP tạm sau khi upload
- **Download về máy khác** khi cần khôi phục
- **Kiểm tra dung lượng đĩa** trước khi nén
- **File cấu hình** linh hoạt, dễ tùy chỉnh

---

## 2. Cài đặt

### Yêu cầu hệ thống

- Windows 10/11
- PowerShell 5.1+
- Kết nối Internet

### Bước 1: Cài đặt rclone

```cmd
winget install rclone.rclone
```

Hoặc tải thủ công:
1. Vào https://github.com/rclone/rclone/releases
2. Tải file `.zip` cho Windows
3. Giải nén vào `C:\Program Files\rclone\` hoặc `C:\Users\YOUR_USER\bin\`

### Bước 2: Cài đặt 7-Zip (tùy chọn)

```cmd
winget install 7zip.7zip
```

> **Lưu ý:** Nếu không cài 7-Zip, script sẽ dùng PowerShell Compress-Archive (chậm hơn)

### Bước 3: Copy thư mục backup_agent

Đặt thư mục `backup_agent` ở vị trí mong muốn, ví dụ:
- `D:\bmad-projects\backup_agent\` (nếu trên máy nguồn)
- `D:\backup_agent\` (nếu trên máy đích)

---

## 3. Cấu hình Google Drive

### Bước 1: Chạy rclone config

Mở PowerShell và chạy:

```powershell
rclone config
```

### Bước 2: Tạo remote mới

```
Current remotes:

Name                 Type
----                 ----
e) Edit existing remote
n) New remote
d) Delete remote
r) Rename remote
c) Copy remote
s) Set configuration password
q) Quit config

e/n/d/r/c/s/q> n
```

### Bước 3: Đặt tên cho remote

```
name> gdrive
```

### Bước 4: Chọn loại storage

```
Type of storage to configure.
Choose a number from below, or type in your own value.
...
XX / Google Drive
   \ "drive"
...
Storage> drive
```

### Bước 5: Client ID & Secret

```
Google Application Client Id
Leave blank normally.
client_id> (để trống, nhấn Enter)

Google Application Client Secret
Leave blank normally.
client_secret> (để trống, nhấn Enter)
```

### Bước 6: Chọn scope

```
Choose a number from below or type in your own value.
...
1 / Full access all files, excluding Application Data Folder.
   \ "drive"
...
scope> 1
```

### Bước 7: Root folder ID

```
ID of the root folder
Leave blank normally.
root_folder_id> (để trống, nhấn Enter)
```

### Bước 8: Service account

```
Service Account Credentials
Leave blank normally.
service_account_file> (để trống, nhấn Enter)
```

### Bước 9: Chỉnh config nâng cao

```
Edit advanced config?
y) Yes
n) No (default)
y/n> n
```

### Bước 10: Xác thực OAuth

```
Use auto config?
y) Yes (default)
n) No
y/n> y
```

Rclone sẽ mở trình duyệt → Đăng nhập Google → Cho phép truy cập.

### Bước 11: Xác nhận

```
Remote config
[gdrive]
type = drive
token = {"access_token":"...","token_type":"Bearer"...}

Make gdrive the default remote?
y) Yes (n) No
y/n> n

Current remotes:

Name                 Type
----                 ----
gdrive              drive

e) Edit existing remote
n) New remote
d) Delete remote
r) Rename remote
c) Copy remote
s) Set configuration password
q) Quit config

e/n/d/r/c/s/q> q
```

### Bước 12: Tạo folder trên Google Drive

Tạo folder `bmad-backups` trên Google Drive (hoặc để script tự tạo).

---

## 4. Sao lưu (Upload)

Sử dụng trên **máy nguồn** (chứa D:\bmad-projects).

### Chạy nhanh nhất

```powershell
cd D:\bmad-projects\backup_agent
.\backup_to_gdrive_v2.ps1
```

### Chạy với batch launcher

```cmd
.\run_backup.bat
```

### Các chế độ chạy

```powershell
# Chạy bình thường
.\backup_to_gdrive_v2.ps1

# Chạy test (chỉ xử lý 3 folder đầu)
.\backup_to_gdrive_v2.ps1 -TestMode

# Chạy với file config khác
.\backup_to_gdrive_v2.ps1 -ConfigPath "path\to\config.json"
```

### Kết quả

Sau khi chạy xong:
- Folder mới trên Google Drive: `bmad-backups/YYYY-MM/`
- File ZIP cho mỗi project
- File MANIFEST summarizing kết quả
- File log chi tiết

---

## 5. Khôi phục (Download)

Sử dụng trên **máy đích** (muốn khôi phục).

### Chạy nhanh nhất

```powershell
cd D:\backup_agent
.\backup_download.ps1 -Mode download
```

### Chạy với batch launcher

```cmd
.\run_download.bat
```

### Các chế độ download

```powershell
# 1. Liệt kê các backup có sẵn
.\backup_download.ps1 -Mode list

# 2. Download backup mới nhất
.\backup_download.ps1 -Mode download

# 3. Download backup cụ thể (theo tháng)
.\backup_download.ps1 -Mode download -BackupDate "2025-06"

# 4. Download và giới hạn số lượng file (test)
.\backup_download.ps1 -Mode download -MaxBackups 5

# 5. Download và tự động giải nén
.\backup_download.ps1 -Mode download -Extract

# 6. Download, giải nén, và xóa ZIP
.\backup_download.ps1 -Mode download -Extract -DeleteZipAfterExtract

# 7. Kiểm tra file đã download
.\backup_download.ps1 -Mode verify
```

### Cấu hình download

Đảm bảo `config.json` có phần `download`:

```json
"download": {
  "destinationDir": "D:\\downloads",
  "batchSize": 3,
  "maxRetries": 3,
  "verifyAfterDownload": true,
  "extractAfterDownload": false
}
```

---

## 6. File cấu hình

File `config.json` chứa tất cả các thiết lập:

```json
{
  "paths": {
    "sourceDir": "D:\\bmad-projects",           // Folder cần backup
    "tempDir": "D:\\backup_agent\\temp",         // Folder tạm cho ZIP
    "gdriveRemote": "gdrive",                   // Tên rclone remote
    "gdriveDest": "bmad-backups"                // Folder trên GDrive
  },

  "steps": {
    "checkDiskSpace": true,                      // Kiểm tra dung lượng
    "zipFolders": true,                          // Nén ZIP
    "uploadToGdrive": true,                      // Upload
    "deleteLocalZip": true,                      // Xóa ZIP sau upload
    "uploadManifest": true                       // Upload MANIFEST
  },

  "mode": {
    "type": "parallel"                           // streaming | batch | parallel
  },

  "upload": {
    "maxRetries": 3,                             // Số lần retry
    "batchSize": 3                               // Số folder xử lý song song
  },

  "folders": {
    "skipList": [                                // Danh sách folder BỎ QUA
      ".claude",
      "_bmad",
      "_bmad-output",
      "backup_agent",
      "temp"
    ]
  },

  "download": {
    "destinationDir": "D:\\downloads",
    "batchSize": 3,
    "maxRetries": 3,
    "verifyAfterDownload": true
  },

  "test": {
    "enabled": false,                            // Bật mode test
    "maxFoldersToProcess": 3                    // Giới hạn folder khi test
  }
}
```

### So sánh chế độ

| Chế độ | Mô tả | Tốc độ | Dùng đĩa |
|--------|-------|---------|----------|
| **streaming** | Zip→Upload→Delete từng folder | Chậm | Ít nhất |
| **batch** | Zip tất cả→Upload tất cả | Nhanh | Nhiều |
| **parallel** | Xử lý batchSize folder song song | **Nhanh nhất** | Vừa |

---

## 7. Xử lý sự cố

### "rclone not found"

**Nguyên nhân:** rclone chưa cài hoặc không có trong PATH.

**Khắc phục:**
```cmd
# Kiểm tra
rclone version

# Nếu không có, cài đặt lại
winget install rclone.rclone
# Hoặc thêm vào PATH manuall
```

### "Remote not found"

**Nguyên nhân:** Chưa cấu hình rclone hoặc sai tên remote.

**Khắc phục:**
```powershell
# Liệt kê các remote
rclone listremotes

# Nếu trống, chạy config lại
rclone config
```

### "Cannot connect to Google Drive"

**Nguyên nhân:** Token hết hạn hoặc chưa xác thực.

**Khắc phục:**
```powershell
# Test kết nối
rclone about gdrive:

# Nếu lỗi, cấu hình lại
rclone config
# Chọn e (Edit) → gdrive → Re-authenticate
```

### "Not enough disk space"

**Nguyên nhân:** Ổ đĩa không đủ chỗ cho ZIP tạm.

**Khắc phục:**
```json
// Tăng margin trong config.json
"spaceCheck": {
  "marginMultiplier": 2.0,     // Tăng từ 1.5
  "failAction": "skip"         // Bỏ qua thay vì dừng
}

// Hoặc giảm batchSize
"upload": {
  "batchSize": 2                // Giảm từ 3
}

// Hoặc chuyển sang streaming mode
"mode": {
  "type": "streaming"
}
```

### "Upload timeout"

**Nguyên nhân:** Kết nối mạng chập chờn hoặc file quá lớn.

**Khắc phục:**
```json
"upload": {
  "maxRetries": 5,             // Tăng số lần retry
  "retryDelaySeconds": 10      // Tăng thời gian chờ
}
```

### "Download verification failed"

**Nguyên nhân:** File ZIP bị lỗi trong quá trình download.

**Khắc phục:**
```powershell
# Download lại file cụ thể
.\backup_download.ps1 -Mode download -BackupDate "2025-06"

# Kiểm tra log
type downloads\download_*.log
```

### Folder muốn backup bị bỏ qua

**Nguyên nhân:** Tên folder nằm trong `skipList`.

**Khắc phục:**
```json
"folders": {
  "skipList": [
    ".claude",
    "_bmad",
    // Xóa tên folder bạn muốn backup khỏi đây
  ]
}
```

---

## Phụ lục: Tệp tin trong backup_agent

```
backup_agent/
├── config.json                  # File cấu hình chính
├── backup_to_gdrive_v2.ps1      # Script upload backup
├── backup_download.ps1          # Script download backup
├── run_backup.bat                # Batch launcher cho upload
├── run_download.bat              # Batch launcher cho download
├── DESIGN.md                     # Tài liệu thiết kế
├── USERGUIDE.md                  # Tài liệu này
├── temp/                         # Folder tạm (ZIP trong quá trình x lý)
├── downloads/                    # Folder download backup về
├── logs/                         # Log files
└── tests/                        # Test scripts
    ├── test_gdrive.ps1
    ├── test_zip.ps1
    ├── test_single_backup.ps1
    └── test_download.ps1
```

---

## Tài liệu tham khảo

- [rclone Documentation](https://rclone.org/docs/)
- [rclone Google Drive Setup](https://rclone.org/drive/)
- [7-Zip Command Line](https://sevenzip.osdn.jp/chm/cmdline/)

---

Phiên bản: 1.0
Ngày tạo: 2025-06-28
