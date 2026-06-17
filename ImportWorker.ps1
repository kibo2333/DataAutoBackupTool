. "$PSScriptRoot\_common.ps1"

$mysqlBinDir = Find-MySqlBin
if ($mysqlBinDir) { $env:PATH = "$mysqlBinDir;$env:PATH"; Write-Log "MySQL bin: $mysqlBinDir" }
else { Write-Log "Warning: MySQL not found in PATH" }
$mysqlExeGlobal = if ($mysqlBinDir) { "$mysqlBinDir\mysql.exe" } else { "mysql.exe" }

$guid = $null
$path = $null
$duplicateOption = "追加导入"

for ($i = 0; $i -lt $args.Length; $i++) {
    if ($args[$i] -eq "-guid" -and $i + 1 -lt $args.Length) {
        $guid = $args[$i + 1]
        $i++
    } elseif ($args[$i] -eq "-path" -and $i + 1 -lt $args.Length) {
        $path = $args[$i + 1]
        $i++
    } elseif ($args[$i] -eq "-duplicateOption" -and $i + 1 -lt $args.Length) {
        $duplicateOption = $args[$i + 1]
        $i++
    }
}

if (-not $guid) {
    Write-Log "[ERROR] GUID parameter is required"
    exit 1
}

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
}

$configPath = Join-Path $PSScriptRoot "config.json"
if (-not (Test-Path $configPath)) {
    Write-Log "[ERROR] Config file not found - $configPath"
    exit 1
}

try {
    $config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Log "[ERROR] Failed to read config file - $_"
    exit 1
}

$mysqlHost = $config.importMysql.host
$mysqlPort = $config.importMysql.port
$mysqlUser = $config.importMysql.user
$mysqlPassword = $config.importMysql.password
$mysqlDatabase = $config.importMysql.database

if (-not [string]::IsNullOrEmpty($path)) {
    $backupRoot = $path.TrimEnd('\')
} else {
    $backupRoot = $config.paths.baseTargetPath
}

$guidDir = Join-Path (Join-Path $backupRoot "data") $guid
if (-not (Test-Path $guidDir)) {
    Write-Log "[ERROR] Backup directory not found - $guidDir"
    exit 1
}

Write-Log "=============================="
Write-Log "Data Import Script v1.0"
Write-Log "=============================="
Write-Log "[INFO] GUID: $guid"
Write-Log "[INFO] Backup Directory: $guidDir"
Write-Log "[INFO] Duplicate Option: $duplicateOption"
Write-Log "[INFO] MySQL Host: $mysqlHost"
Write-Log "[INFO] MySQL Database: $mysqlDatabase"

function DeleteExistingGuidData {
    param([string]$guidToDelete)

    Write-Log "[INFO] Deleting existing data for GUID: $guidToDelete"

    $argsList = @(
        "--host=$mysqlHost",
        "--port=$mysqlPort",
        "--user=$mysqlUser",
        "--password=$mysqlPassword",
        "--database=$mysqlDatabase",
        "--default-character-set=utf8mb4",
        "--connect-timeout=15",
        "--execute=START TRANSACTION; DELETE FROM rep_lot WHERE GUID='$guidToDelete'; DELETE FROM rep_frame WHERE GUID LIKE '$guidToDelete%'; DELETE FROM rep_result WHERE GUID LIKE '$guidToDelete%'; DELETE FROM rep_unit WHERE GUID LIKE '$guidToDelete%'; DELETE FROM sys_defect WHERE GUID LIKE '$guidToDelete%'; DELETE FROM sys_unit WHERE GUID LIKE '$guidToDelete%'; COMMIT;"
    )

    $output = & $mysqlExeGlobal $argsList 2>&1
    $hasError = $false

    foreach ($line in $output) {
        if ($line -notlike "*Using a password*") {
            if ($line -like "*ERROR*" -or $line -like "*error*") {
                Write-Log "[ERROR] $line"
                $hasError = $true
            }
        }
    }

    if ($hasError) {
        Write-Log "[ERROR] DeleteExistingGuidData failed"
        return $false
    }
    return $true
}

function TruncateAllTables {
    Write-Log "[INFO] Truncating all tables in database"

    $argsList = @(
        "--host=$mysqlHost",
        "--port=$mysqlPort",
        "--user=$mysqlUser",
        "--password=$mysqlPassword",
        "--database=$mysqlDatabase",
        "--default-character-set=utf8mb4",
        "--connect-timeout=15",
        "--execute=SET FOREIGN_KEY_CHECKS=0; TRUNCATE TABLE rep_lot; TRUNCATE TABLE rep_frame; TRUNCATE TABLE rep_result; TRUNCATE TABLE rep_unit; TRUNCATE TABLE sys_defect; TRUNCATE TABLE sys_unit; SET FOREIGN_KEY_CHECKS=1;"
    )

    $output = & $mysqlExeGlobal $argsList 2>&1
    $hasError = $false

    foreach ($line in $output) {
        if ($line -notlike "*Using a password*") {
            if ($line -like "*ERROR*" -or $line -like "*error*") {
                Write-Log "[ERROR] $line"
                $hasError = $true
            }
        }
    }

    if ($hasError) {
        Write-Log "[ERROR] TruncateAllTables failed"
        return $false
    }
    return $true
}

$sqlFiles = Get-ChildItem -Path $guidDir -Filter "*.sql" | Where-Object {
    $_.Name -notlike "*_schema.sql" -and $_.Name -ne "schema.sql"
}

if (-not $sqlFiles) {
    Write-Log "[WARNING] No SQL data files found in $guidDir"
    exit 0
}

Write-Log "[Step 1] Starting data import..."
Write-Log "[INFO] Found $($sqlFiles.Count) SQL files to import"

# ponytail: 任何模式都先删此 GUID 的旧数据——不清则后续 INSERT 撞重复键拖死
if ($duplicateOption -eq "清空后导入") {
    if (-not (TruncateAllTables)) {
        Write-Log "[ERROR] Truncate failed, import aborted"
        exit 1
    }
} else {
    # "覆盖重复" 和 "追加导入" 都先清除此 GUID 的数据，保证 INSERT 无冲突
    if (-not (DeleteExistingGuidData -guidToDelete $guid)) {
        Write-Log "[ERROR] Delete failed, import aborted"
        exit 1
    }
}

# ponytail: 合并所有 SQL 文件到一次 mysql.exe 调用，避免重复 TCP 连接握手
# ponytail: 包裹事务 + 禁用约束检查，避免逐行 autocommit
# ponytail: 不用 Out-Null —— 它枚举 StringBuilder 每个字符，66MB SQL 卡死 5 分钟
Write-Log "[Step 2] Concatenating SQL files for single-pass import..."
$combinedSql = New-Object System.Text.StringBuilder
$null = $combinedSql.AppendLine("SET FOREIGN_KEY_CHECKS=0;")
$null = $combinedSql.AppendLine("SET UNIQUE_CHECKS=0;")
$null = $combinedSql.AppendLine("START TRANSACTION;")
foreach ($sqlFile in $sqlFiles) {
    Write-Log "[PROCESS] Queuing: $($sqlFile.Name)"
    $content = Get-Content -Path $sqlFile.FullName -Raw -Encoding UTF8
    $null = $combinedSql.Append($content)
    $null = $combinedSql.AppendLine()
}
$null = $combinedSql.AppendLine("COMMIT;")
$null = $combinedSql.AppendLine("SET UNIQUE_CHECKS=1;")
$null = $combinedSql.AppendLine("SET FOREIGN_KEY_CHECKS=1;")

$argsList = @(
    "--host=$mysqlHost",
    "--port=$mysqlPort",
    "--user=$mysqlUser",
    "--password=$mysqlPassword",
    "--database=$mysqlDatabase",
    "--default-character-set=utf8mb4",
    "--connect-timeout=15",
    "--batch",
    "--force"
)

Write-Log "[STEP 3] Executing single mysql.exe with all SQL data..."
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $mysqlExeGlobal
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.Arguments = $argsList -join ' '
    $proc = [System.Diagnostics.Process]::Start($psi)
    # ponytail: 必须异步读管道——不读则缓冲区满后 mysql 的写操作阻塞，死锁 WaitForExit
    $mysqlOutput = New-Object System.Text.StringBuilder
    $mysqlError = New-Object System.Text.StringBuilder
    $null = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action {
        [void]$mysqlOutput.AppendLine($event.SourceEventArgs.Data)
    }
    $null = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action {
        [void]$mysqlError.AppendLine($event.SourceEventArgs.Data)
    }
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
    $proc.StandardInput.WriteLine($combinedSql.ToString())
    $proc.StandardInput.Close()
    # ponytail: 10 分钟超时防止 mysql.exe 无限挂起（死锁、网络断开等）
    $timeoutSeconds = 600
    if (-not $proc.WaitForExit($timeoutSeconds * 1000)) {
        Write-Log "[ERROR] mysql.exe timed out after ${timeoutSeconds}s, killing process"
        $proc.Kill()
        $proc.WaitForExit(5000)
        $LASTEXITCODE = -1
    } else {
        $LASTEXITCODE = $proc.ExitCode
    }
    $capturedOutput = $mysqlOutput.ToString().Trim()
    $capturedError = $mysqlError.ToString().Trim()
    if ($capturedOutput) { Write-Log "[MYSQL] $capturedOutput" }
    if ($capturedError) { Write-Log "[MYSQL-ERR] $capturedError" }
    # 清理事件订阅防止内存泄漏
    Get-EventSubscriber | Unregister-Event -Force -ErrorAction SilentlyContinue | Out-Null
} catch {
    Write-Log "[EXCEPTION] $_"
    # 清理事件订阅防止泄漏
    Get-EventSubscriber | Unregister-Event -Force -ErrorAction SilentlyContinue | Out-Null
    $LASTEXITCODE = 1
}

$hasError = $LASTEXITCODE -ne 0
if ($hasError) {
    Write-Log "[ERROR] mysql.exe exited with code $LASTEXITCODE"
}

$successCount = if ($hasError) { 0 } else { $sqlFiles.Count }

Write-Log ""
Write-Log "Import completed!"
Write-Log "[RESULT] Successfully imported $successCount files"

if ($hasError) { exit 1 }
Write-Log "[SUCCESS] All data imported successfully!"
exit 0
