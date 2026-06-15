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
$logFile = Join-Path $repoRoot "auto_backup_log.txt"
$lastRunFile = Join-Path $repoRoot "last_backup_run.txt"

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

function Write-ErrorLog {
    param([string]$message, [string]$exception = $null)
    $errorMsg = "ERROR: $message"
    if ($exception) { $errorMsg += " | Exception: $exception" }
    Write-Log -message $errorMsg -level "ERROR"
}

function Write-WarningLog {
    param([string]$message)
    Write-Log -message $message -level "WARNING"
}

function Update-LastRunTime {
    param([string]$status, [string]$errorMessage = $null)
    try {
        $lastRun = [PSCustomObject]@{
            Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Status = $status
            ErrorMessage = $errorMessage
        }
        $lastRun | ConvertTo-Json | Set-Content -Path $lastRunFile -Encoding UTF8
    } catch {
        Write-WarningLog "Failed to update last run time: $_"
    }
}

function Test-MySqlConnection {
    param(
        [string]$mysqlHost, [string]$mysqlPort,
        [string]$mysqlUser, [string]$mysqlPassword, [string]$mysqlDatabase
    )
    try {
        Write-Log "Testing MySQL connection to ${mysqlHost}:${mysqlPort}"
        $mysqlExe = if ($mysqlBinDir) { "$mysqlBinDir\mysql.exe" } else { "mysql.exe" }
        $result = & $mysqlExe --host=$mysqlHost --port=$mysqlPort --user=$mysqlUser --password=$mysqlPassword --database=$mysqlDatabase -e "SELECT 1" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "MySQL connection test successful"
            return $true
        } else {
            Write-ErrorLog "MySQL connection test failed: $($result -join '; ')"
            return $false
        }
    } catch {
        Write-ErrorLog "Exception during MySQL connection test: $_"
        return $false
    }
}

function Test-GuidValid {
    param([string]$inputGuid)
    $cleanGuid = $inputGuid.Replace('-', '')
    if ($cleanGuid.Length -ne 32 -or $cleanGuid -notmatch '^[0-9a-fA-F]{32}$') { return $false }
    return $true
}

function Test-CancelSignal {
    try {
        $cancelEvent = [System.Threading.EventWaitHandle]::OpenExisting("Global\DataBackupTool_Cancel")
        if ($cancelEvent -ne $null) {
            $signaled = $cancelEvent.WaitOne(0)
            $cancelEvent.Dispose()
            return $signaled
        }
    } catch { }
    return $false
}

function Get-AllGuids {
    param([string]$mysqlHost, [string]$mysqlPort, [string]$user, [string]$password, [string]$database)
    $guids = @()
    try {
        $query = "SELECT GUID FROM rep_lot"
        $mysqlExe = if ($mysqlBinDir) { "$mysqlBinDir\mysql.exe" } else { "mysql.exe" }
        $output = & $mysqlExe --host=$mysqlHost --port=$mysqlPort --user=$user --password=$password --database=$database --default-character-set=utf8mb4 -N -e $query 2>&1
        foreach ($line in $output) {
            if ($line -like "*Using a password on the command line interface can be insecure.*") { continue }
            if ($line -like "*ERROR*" -or $line -like "*error*") { Write-Log "Database query error: $line"; return $guids }
            if ($LASTEXITCODE -eq 0 -and $line -is [string] -and $line.Trim() -ne "") {
                $guid = $line.Trim()
                if (Test-GuidValid $guid) { $guids += $guid }
            }
        }
    } catch {
        Write-Log "Exception in Get-AllGuids: $_"
    }
    return $guids
}
function Save-OperationRecord {
    param(
        [string]$guid, [string]$operationType, [string]$status,
        [string]$backupPath, [string]$startTime, [string]$log, [string]$createTime
    )
    try {
        $record = [PSCustomObject]@{
            GUID = $guid
            OperationType = $operationType
            Status = $status
            BackupPath = $backupPath
            StartTime = $startTime
            Log = $log
            CreateTime = $createTime
        }
        $recordsPath = Join-Path $repoRoot "backup_records.json"
        if (Test-Path $recordsPath) {
            try {
                $records = Get-Content $recordsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {
                Write-WarningLog "backup_records.json 解析失败，将重建: $_"
                $records = @()
            }
            if ($records -eq $null) {
                $records = @()
            } elseif ($records -isnot [System.Array]) {
                $records = @($records)
            }
        } else {
            $records = @()
        }
        $records += $record
        $records | ConvertTo-Json -Depth 10 | Set-Content -Path $recordsPath -Encoding UTF8
    } catch {
        Write-Log "Failed to save operation record: $_"
    }
}

function Backup-Batch {
    param([string]$guid, [string]$repoRoot, [string]$backupRoot, [string]$backupContent)
    $success = $true
    $startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $imageCopyScript = Join-Path $repoRoot "imagecopy.ps1"
    $guidDataScript = Join-Path $repoRoot "GUID-Data.ps1"
    $schemaScript = Join-Path $repoRoot "schema.ps1"
    Write-Log "Starting backup for GUID: $guid (Content: $backupContent, Backup Root: $backupRoot)"
    $backupImage = $backupContent -eq "OnlyImages" -or $backupContent -eq "ImagesAndData"
    $backupData = $backupContent -eq "OnlyData" -or $backupContent -eq "ImagesAndData"

    if ($backupImage) {
        if (-not (Test-Path $imageCopyScript)) { Write-Log "Script not found: $imageCopyScript"; return $false }
        try {
            Write-Log "Running imagecopy.ps1..."
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-ExecutionPolicy Bypass -File `"$imageCopyScript`" -guid `"$guid`" -backupRoot `"$backupRoot`""
            $psi.WorkingDirectory = $repoRoot
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
            $process = [System.Diagnostics.Process]::Start($psi)
            $output = $process.StandardOutput.ReadToEnd()
            $errorOutput = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($output) { Write-Log $output }
            if ($errorOutput -and !$errorOutput.Contains("Using a password on the command line interface can be insecure")) { Write-Log "错误: $errorOutput" }
            if ($process.ExitCode -ne 0) { Write-Log "imagecopy.ps1 failed with exit code: $($process.ExitCode)"; $success = $false }
        } catch { Write-Log "Exception in imagecopy.ps1: $_"; $success = $false }
    }

    if ($backupData) {
        if (-not (Test-Path $guidDataScript)) { Write-Log "Script not found: $guidDataScript"; return $false }
        if (-not (Test-Path $schemaScript)) { Write-Log "Script not found: $schemaScript"; return $false }
        try {
            Write-Log "Running GUID-Data.ps1..."
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-ExecutionPolicy Bypass -File `"$guidDataScript`" -guid `"$guid`" -backupRoot `"$backupRoot`""
            $psi.WorkingDirectory = $repoRoot
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
            $process = [System.Diagnostics.Process]::Start($psi)
            $output = $process.StandardOutput.ReadToEnd()
            $errorOutput = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($output) { Write-Log $output }
            if ($errorOutput -and !$errorOutput.Contains("Using a password on the command line interface can be insecure")) { Write-Log "错误: $errorOutput" }
            if ($process.ExitCode -ne 0) { Write-Log "GUID-Data.ps1 failed with exit code: $($process.ExitCode)"; $success = $false }
        } catch { Write-Log "Exception in GUID-Data.ps1: $_"; $success = $false }
        try {
            Write-Log "Running schema.ps1..."
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-ExecutionPolicy Bypass -File `"$schemaScript`" -guid `"$guid`" -path `"$backupRoot`""
            $psi.WorkingDirectory = $repoRoot
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
            $process = [System.Diagnostics.Process]::Start($psi)
            $output = $process.StandardOutput.ReadToEnd()
            $errorOutput = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($output) { Write-Log $output }
            if ($errorOutput -and !$errorOutput.Contains("Using a password on the command line interface can be insecure")) { Write-Log "错误: $errorOutput" }
            if ($process.ExitCode -ne 0) { Write-Log "schema.ps1 failed with exit code: $($process.ExitCode)"; $success = $false }
        } catch { Write-Log "Exception in schema.ps1: $_"; $success = $false }
    }

    $createTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $status = if ($success) { "成功" } else { "失败" }
    $log = if ($success) { "自动备份完成" } else { "自动备份失败" }
    Save-OperationRecord -guid $guid -operationType "备份" -status $status -backupPath "" -startTime $startTime -log $log -createTime $createTime
    return $success
}
$startTime = Get-Date
$startTimeStr = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
Write-Log "=============================="
Write-Log "Auto Backup Script v2.0 - Enhanced Error Handling"
Write-Log "=============================="
Write-Log "Script started at: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Log "Running as user: $env:USERNAME"
Write-Log "Running from: $repoRoot"

$mutexName = "Global\DataBackupTool_Mutex"
try {
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
} catch {
    Write-WarningLog "Failed to create mutex, proceeding without lock: $_"
    $mutex = $null
}

$exitCode = 0
$errorMessage = $null

if ($mutex -ne $null -and -not $mutex.WaitOne(0)) {
    Write-Log "Backup is already running, exiting..."
    $mutex.Dispose()
    Update-LastRunTime -status "SKIPPED" -errorMessage "Backup already running"
    exit 0
}

try {
    $configPath = Join-Path $repoRoot "config.json"
    $configTxtPath = Join-Path $repoRoot "config.txt"
    Write-Log "Checking configuration files..."
    if (-not (Test-Path $configPath)) {
        $errorMessage = "Config file not found: $configPath"
        Write-ErrorLog $errorMessage
        $exitCode = 1
        Update-LastRunTime -status "FAILED" -errorMessage $errorMessage
        return
    }
    Write-Log "Reading configuration from: $configPath"
    try {
        $config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $errorMessage = "Failed to parse config.json: $_"
        Write-ErrorLog $errorMessage
        $exitCode = 1
        Update-LastRunTime -status "FAILED" -errorMessage $errorMessage
        return
    }
    Write-Log "Extracting database connection parameters..."
    try {
        $mysqlHost = $config.backupMysql.host
        $mysqlPort = $config.backupMysql.port
        $mysqlUser = $config.backupMysql.user
        $mysqlPassword = $config.backupMysql.password
        $mysqlDatabase = $config.backupMysql.database
        Write-Log "Database: ${mysqlHost}:${mysqlPort}/${mysqlDatabase}"
        Write-Log "User: $mysqlUser"
    } catch {
        $errorMessage = "Failed to extract database configuration: $_"
        Write-ErrorLog $errorMessage
        $exitCode = 1
        Update-LastRunTime -status "FAILED" -errorMessage $errorMessage
        return
    }
    Write-Log "Testing database connection..."
    if (-not (Test-MySqlConnection -mysqlHost $mysqlHost -mysqlPort $mysqlPort -mysqlUser $mysqlUser -mysqlPassword $mysqlPassword -mysqlDatabase $mysqlDatabase)) {
        $errorMessage = "Database connection failed"
        Write-ErrorLog $errorMessage
        $exitCode = 1
        Update-LastRunTime -status "FAILED" -errorMessage $errorMessage
        return
    }

    $backupRoot = $repoRoot
    if (Test-Path $configTxtPath) {
        Write-Log "Reading backup root path from config.txt"
        $configLines = Get-Content -Path $configTxtPath -Encoding UTF8
        foreach ($line in $configLines) {
            if ($line -match "^BackupRoot=(.+)$") {
                $backupRoot = $matches[1].Trim()
                Write-Log "Backup root path configured as: $backupRoot"
                break
            }
        }
    } else {
        Write-WarningLog "config.txt not found, using default backup root: $repoRoot"
    }

    $backupContent = "ImagesAndData"
    if (Test-Path $configTxtPath) {
        Write-Log "Reading backup content setting from config.txt"
        $configLines = Get-Content -Path $configTxtPath -Encoding UTF8
        foreach ($line in $configLines) {
            if ($line -match "^BackupContent=(.+)$") {
                $backupContent = $matches[1]
                Write-Log "Backup content configured as: $backupContent"
                $backupContent = $backupContent.Trim()
                if ($backupContent -eq "仅图片" -or $backupContent -eq "OnlyImages") {
                    $backupContent = "OnlyImages"
                } elseif ($backupContent -eq "仅数据" -or $backupContent -eq "OnlyData") {
                    $backupContent = "OnlyData"
                } else {
                    $backupContent = "ImagesAndData"
                }
                Write-Log "Converted backup content to: $backupContent"
                break
            }
        }
    } else {
        Write-WarningLog "config.txt not found, using default backup content: $backupContent"
    }

    Write-Log "Getting all GUIDs from database..."
    $guids = Get-AllGuids -mysqlHost $mysqlHost -mysqlPort $mysqlPort -user $mysqlUser -password $mysqlPassword -database $mysqlDatabase
    if ($guids.Count -eq 0) {
        Write-Log "No batches found in database, exiting"
        $exitCode = 0
        Update-LastRunTime -status "SUCCESS" -errorMessage "No batches to backup"
        return
    }
    Write-Log "Found $($guids.Count) batches to backup"

    $successCount = 0
    $failCount = 0
    $totalCount = $guids.Count
    $errors = @()
    $finalStatus = $null

    foreach ($guid in $guids) {
        if (Test-CancelSignal) {
            Write-Log "检测到取消信号，自动备份已终止"
            $finalStatus = "CANCELLED"
            break
        }
        $batchStartTime = Get-Date
        Write-Log "Processing GUID: $guid ($($successCount + $failCount + 1)/$totalCount)"
        try {
            if (Backup-Batch -guid $guid -repoRoot $repoRoot -backupRoot $backupRoot -backupContent $backupContent) {
                $duration = (Get-Date) - $batchStartTime
                Write-Log "Successfully backed up GUID: $guid (Duration: $($duration.TotalSeconds) seconds)"
                $successCount++
            } else {
                Write-ErrorLog "Failed to backup GUID: $guid"
                $errors += "GUID $guid backup failed"
                $failCount++
            }
        } catch {
            Write-ErrorLog "Exception while processing GUID $guid : $_"
            $errors += "GUID $guid exception: $_"
            $failCount++
        }
    }

    Write-Log "Backup processing completed"
    Write-Log "Total: $totalCount, Success: $successCount, Failed: $failCount"
    if ($failCount -gt 0) {
        $exitCode = 1
        Write-ErrorLog "Some backups failed. See errors below:"
        foreach ($err in $errors) {
            Write-ErrorLog $err
        }
    }
    if ($finalStatus -ne "CANCELLED") {
        $finalStatus = if ($exitCode -eq 0) { "SUCCESS" } else { "PARTIAL" }
    }
    $finalErrorMessage = if ($errors) { $errors -join "; " } else { $null }
    Update-LastRunTime -status $finalStatus -errorMessage $finalErrorMessage
}
catch {
    $errorMessage = "Unexpected error during auto backup: $_"
    Write-ErrorLog $errorMessage
    $exitCode = 1
    Update-LastRunTime -status "FAILED" -errorMessage $errorMessage
}
finally {
    if ($mutex -ne $null) {
        try {
            $mutex.ReleaseMutex()
        } catch {
            Write-WarningLog "Failed to release mutex: $_"
        }
        $mutex.Dispose()
    }
}

$totalDuration = (Get-Date) - $startTime
Write-Log "=============================="
Write-Log "Auto backup completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Total duration: $($totalDuration.TotalSeconds) seconds"
Write-Log "Exit code: $exitCode"
Write-Log "=============================="

exit $exitCode