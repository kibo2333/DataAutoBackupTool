param([Parameter(Position=0)][string]$guid)

[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'UTF8'

function Write-Log { param([string]$message); [Console]::WriteLine($message) }

# 查找 MySQL 可执行文件路径
function Find-MySqlBin {
    $cmd = Get-Command "mysql.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path $cmd.Source }
    $services = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services" -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match "^MySQL" }
    foreach ($svc in $services) {
        $imgPath = (Get-ItemProperty $svc.PSPath -ErrorAction SilentlyContinue).ImagePath
        if ($imgPath) {
            $binDir = Split-Path ($imgPath -replace '"','').Trim()
            if ($binDir -and (Test-Path (Join-Path $binDir "mysql.exe"))) { return $binDir }
        }
    }
    $fixedPaths = @("E:\MySQL\MySQL Server 8.0\bin", "D:\MySQL\MySQL Server 8.0\bin")
    foreach ($path in $fixedPaths) {
        if (Test-Path (Join-Path $path "mysql.exe")) { return $path }
    }
    return $null
}

$mysqlBinDir = Find-MySqlBin
if ($mysqlBinDir) { $env:PATH = "$mysqlBinDir;$env:PATH" }

if ([string]::IsNullOrEmpty($guid)) { Write-Log "Error: -guid parameter required"; exit 1 }

# 校验 GUID 格式
$cleanGuid = $guid.Replace('-', '').ToLower()
if ($cleanGuid.Length -ne 32 -or $cleanGuid -notmatch '^[0-9a-fA-F]{32}$') { Write-Log "Error: Invalid GUID format"; exit 1 }

$repoRoot = $PSScriptRoot
$configPath = Join-Path $repoRoot "config.json"
if (-not (Test-Path $configPath)) { Write-Log "Error: config.json not found"; exit 1 }
try { $config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Write-Log "Error: Failed to parse config.json - $_"; exit 1 }

# 从配置读取数据库连接参数
$mysqlHost = $config.backupMysql.host
$mysqlport = $config.backupMysql.port
$mysqlUser = $config.backupMysql.user
$mysqlPassword = $config.backupMysql.password
$mysqlDatabase = $config.backupMysql.database

Write-Log "Config: host=$mysqlHost, port=$mysqlport, database=$mysqlDatabase"

Write-Log "=============================="
Write-Log "Delete Data Script v1.0"
Write-Log "=============================="
Write-Log "GUID: $cleanGuid"

# 获取 detectionsSHA256，用于删除 rep_detections 表数据
function Get-DetectionsSHA256 {
    param([string]$guid)
    $query = "SELECT detectionsSHA256 FROM rep_lot WHERE GUID = '$guid';"
    $mysqlExe = if ($mysqlBinDir) { "$mysqlBinDir\mysql.exe" } else { "mysql.exe" }
    $result = & $mysqlExe "-h$mysqlHost" "-P$mysqlport" "-u$mysqlUser" "-p$mysqlPassword" "-D$mysqlDatabase" "--default-character-set=utf8mb4" -N -e $query 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    $result = $result | Where-Object { $_ -notlike "*Using a password*" }
    if ($result -is [array]) { $result = $result[0] }
    if ([string]::IsNullOrEmpty($result) -or $result -match '^NULL$') { return $null }
    return $result.ToString().Trim()
}

# 删除指定表中符合条件的数据，返回删除行数
function Delete-TableData {
    param([string]$tableName, [string]$whereClause, [string]$description)
    Write-Log "Deleting $tableName ()..."
    $query = "DELETE FROM $tableName WHERE $whereClause; SELECT ROW_COUNT();"
    $output = & $mysqlExe "-h$mysqlHost" "-P$mysqlport" "-u$mysqlUser" "-p$mysqlPassword" "-D$mysqlDatabase" "--default-character-set=utf8mb4" -N -e $query 2>&1
    if ($LASTEXITCODE -eq 0) {
        $output = $output | Where-Object { $_ -notlike "*Using a password*" }
        if ($output -is [array] -and $output.Length -gt 0) { $affectedRows = $output[-1] }
        else { $affectedRows = $output }
        if (-not [string]::IsNullOrEmpty($affectedRows)) {
            $rows = [int]$affectedRows
            if ($rows -lt 0) { Write-Log "Deleted 0 rows"; return 0 }
            Write-Log "Deleted $rows rows"
            return $rows
        } else { Write-Log "Deleted 0 rows"; return 0 }
    } else {
        Write-Log "Delete failed: $output"
        Write-Log "Possible cause: connection failed or insufficient permissions"
        return 0
    }
}

# 按表逐个删除数据
Write-Log "`n[Step 1] Deleting data..."
$totalDeleted = 0

$deleted = Delete-TableData -tableName "rep_lot" -whereClause "GUID = '$cleanGuid'" -description "by GUID"
$totalDeleted += $deleted
$deleted = Delete-TableData -tableName "rep_frame" -whereClause "GUID = '$cleanGuid'" -description "by GUID"
$totalDeleted += $deleted
$deleted = Delete-TableData -tableName "rep_unit" -whereClause "GUID = '$cleanGuid'" -description "by GUID"
$totalDeleted += $deleted
$deleted = Delete-TableData -tableName "rep_result" -whereClause "GUID = '$cleanGuid'" -description "by GUID"
$totalDeleted += $deleted

Write-Log "`n[Step 2] Query detectionsSHA256..."
$detectionsSHA256 = Get-DetectionsSHA256 -guid $cleanGuid
if (-not [string]::IsNullOrEmpty($detectionsSHA256)) {
    Write-Log "detectionsSHA256: $detectionsSHA256"
    $deleted = Delete-TableData -tableName "rep_detections" -whereClause "recipeSHA256 = '$detectionsSHA256'" -description "by recipeSHA256"
    $totalDeleted += $deleted
} else { Write-Log "Warning: detectionsSHA256 is empty, skipping rep_detections" }

# sys_defect 表删除全部（无 WHERE 条件）
$deleted = Delete-TableData -tableName "sys_defect" -whereClause "1=1" -description "all"
$totalDeleted += $deleted

Write-Log "`n[Step 3] Delete complete!"
Write-Log "Total deleted: $totalDeleted rows"
if ($totalDeleted -eq 0) {
    Write-Log "Warning: No rows deleted"
    Write-Log "Check: 1) GUID correct? 2) DB connection OK? 3) Data already deleted?"
    exit 1
}
exit 0