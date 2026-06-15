# 强制使用 UTF-8 编码读取脚本文件（解决中文注释乱码问题）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'UTF8'

# 设置 PowerShell 使用 UTF-8 作为默认编码
$OutputEncoding = [System.Text.Encoding]::UTF8

# 查找 MySQL 可执行文件路径
function Find-MySqlBin {
    $cmd = Get-Command "mysql.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path $cmd.Source }
    $services = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services" -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match "^MySQL" }
    foreach ($svc in $services) {
        $imgPath = (Get-ItemProperty $svc.PSPath -ErrorAction SilentlyContinue).ImagePath
        if ($imgPath) {
            $binDir = Split-Path ($imgPath -replace '"', '').Trim()
            if ($binDir -and (Test-Path (Join-Path $binDir "mysql.exe"))) { return $binDir }
        }
    }
    $fixedPaths = @("E:\MySQL\MySQL Server 8.0\bin", "D:\MySQL\MySQL Server 8.0\bin")
    foreach ($fixedPath in $fixedPaths) {
        if (Test-Path (Join-Path $fixedPath "mysql.exe")) { return $fixedPath }
    }
    return $null
}

$mysqlBinDir = Find-MySqlBin
if ($mysqlBinDir) {
    $env:PATH = "$mysqlBinDir;$env:PATH"
} else {
    Write-Host "警告: 未找到 MySQL，请确保 mysql.exe 在 PATH 中"
}

$scriptPath = $MyInvocation.MyCommand.Definition
$repoRoot = Split-Path -Path $scriptPath -Parent
if ([string]::IsNullOrEmpty($repoRoot)) {
    $repoRoot = $PSScriptRoot
}
if ([string]::IsNullOrEmpty($repoRoot)) {
    $repoRoot = Split-Path -Path (Get-Location) -Parent
}
$logFile = Join-Path $repoRoot "delete_backup_log.txt"

function Write-Log {
    param([string]$message, [string]$level = "INFO")
    
    $timestampPattern = '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]'
    if ($message -match $timestampPattern) {
        $logMessage = $message
    } else {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$level] $message"
    }
    
    try {
        Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
        [Console]::WriteLine($logMessage)
    } catch {
        [Console]::WriteLine("Failed to write to log file: $_")
    }
}

function Test-GuidValid {
    param([string]$inputGuid)
    $cleanGuid = $inputGuid.Replace('-', '')
    if ($cleanGuid.Length -ne 32 -or $cleanGuid -notmatch '^[0-9a-fA-F]{32}$') {
        return $false
    }
    return $true
}

$startTime = Get-Date
Write-Log "=============================="
Write-Log "Delete Backup Script v1.0"
Write-Log "=============================="
Write-Log "Script started at: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Log "Running as user: $env:USERNAME"
Write-Log "Running from: $repoRoot"

$guid = $null
$path = $null

for ($i = 0; $i -lt $args.Length; $i++) {
    if ($args[$i] -eq "-guid" -and $i + 1 -lt $args.Length) {
        $guid = $args[$i + 1]
        $i++
    } elseif ($args[$i] -eq "-path" -and $i + 1 -lt $args.Length) {
        $path = $args[$i + 1]
        $i++
    }
}

if (-not $guid) {
    Write-Log "[ERROR] GUID parameter is required"
    exit 1
}

if (-not [string]::IsNullOrEmpty($path)) {
    $backupRoot = $path.TrimEnd('\')
} else {
    $configTxtPath = Join-Path $repoRoot "config.txt"
    if (Test-Path $configTxtPath) {
        $configLines = Get-Content -Path $configTxtPath -Encoding UTF8
        foreach ($line in $configLines) {
            if ($line -match "^BackupRoot=(.+)$") {
                $backupRoot = $matches[1].Trim()
                break
            }
        }
    }
    if ([string]::IsNullOrEmpty($backupRoot)) {
        $backupRoot = $repoRoot
    }
}

$cleanGuid = $guid.Replace('-', '').ToLower()
Write-Log "GUID: $cleanGuid"
Write-Log "Backup Root: $backupRoot"

# 计算 GUID 目录路径
$guidImagesFolder = Join-Path $backupRoot "vtImages_2D\images\$cleanGuid"
$guidDataFolder = Join-Path $backupRoot "data\$cleanGuid"
$guidSchemaFolder = Join-Path $backupRoot "schema\$cleanGuid"

Write-Log "Images folder: $guidImagesFolder"
Write-Log "Data folder: $guidDataFolder"
Write-Log "Schema folder: $guidSchemaFolder"

$deletedFolders = 0
$failedFolders = 0

# 删除图片备份
if (Test-Path $guidImagesFolder) {
    try {
        Write-Log "[PROCESS] Deleting images folder: $guidImagesFolder"
        Remove-Item -Path $guidImagesFolder -Recurse -Force
        Write-Log "[SUCCESS] Images folder deleted"
        $deletedFolders++
    } catch {
        Write-Log "[ERROR] Failed to delete images folder: $_"
        $failedFolders++
    }
} else {
    Write-Log "[INFO] Images folder not found (no action needed)"
}

# 删除数据备份
if (Test-Path $guidDataFolder) {
    try {
        Write-Log "[PROCESS] Deleting data folder: $guidDataFolder"
        Remove-Item -Path $guidDataFolder -Recurse -Force
        Write-Log "[SUCCESS] Data folder deleted"
        $deletedFolders++
    } catch {
        Write-Log "[ERROR] Failed to delete data folder: $_"
        $failedFolders++
    }
} else {
    Write-Log "[INFO] Data folder not found (no action needed)"
}

# 删除 schema 备份
if (Test-Path $guidSchemaFolder) {
    try {
        Write-Log "[PROCESS] Deleting schema folder: $guidSchemaFolder"
        Remove-Item -Path $guidSchemaFolder -Recurse -Force
        Write-Log "[SUCCESS] Schema folder deleted"
        $deletedFolders++
    } catch {
        Write-Log "[ERROR] Failed to delete schema folder: $_"
        $failedFolders++
    }
} else {
    Write-Log "[INFO] Schema folder not found (no action needed)"
}

# 从备份记录中删除此 GUID
$recordsPath = Join-Path $repoRoot "backup_records.json"
if (Test-Path $recordsPath) {
    try {
        $records = Get-Content -Path $recordsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($records -ne $null -and $records -is [System.Array]) {
            $originalCount = $records.Count
            $records = $records | Where-Object { $_.GUID -ne $cleanGuid -and $_.GUID -ne $guid }
            $newCount = if ($records -is [System.Array]) { $records.Count } elseif ($records -eq $null) { 0 } else { 1 }
            if ($originalCount -ne $newCount) {
                $records | ConvertTo-Json -Depth 10 | Set-Content -Path $recordsPath -Encoding UTF8
                Write-Log "[INFO] Removed $($originalCount - $newCount) record(s) from backup_records.json"
            } else {
                Write-Log "[INFO] No matching records found in backup_records.json"
            }
        }
    } catch {
        Write-Log "[WARNING] Failed to update backup_records.json: $_"
    }
}

Write-Log ""
Write-Log "=============================="
Write-Log "Delete backup completed"
Write-Log "Deleted folders: $deletedFolders"
Write-Log "Failed folders: $failedFolders"
$totalDuration = (Get-Date) - $startTime
Write-Log "Total duration: $($totalDuration.TotalSeconds) seconds"
Write-Log "=============================="

if ($failedFolders -gt 0) {
    exit 1
}
exit 0