# -*- coding: utf-8 -*-
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'UTF8'
$OutputEncoding = [System.Text.Encoding]::UTF8
[System.GC]::Collect()
$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$message)
    [Console]::WriteLine($message)
}

# 写到标准错误流，供 C# 程序捕获作为错误信息
function Write-ErrorMsg {
    param([string]$message)
    [Console]::Error.WriteLine($message)
}

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
            if ($binDir -and (Test-Path (Join-Path $binDir "mysql.exe"))) {
                return $binDir
            }
        }
    }
    $fixedPaths = @("E:\MySQL\MySQL Server 8.0\bin", "D:\MySQL\MySQL Server 8.0\bin")
    foreach ($fixedPath in $fixedPaths) {
        if (Test-Path (Join-Path $fixedPath "mysql.exe")) { return $fixedPath }
    }
    return $null
}

$mysqlBinDir = Find-MySqlBin
if ($mysqlBinDir) { $env:PATH = "$mysqlBinDir;$env:PATH"; Write-Log "MySQL bin: $mysqlBinDir" }
else { Write-Log "Warning: MySQL not found in PATH" }

# 手动解析参数：-guid / -path / -backupRoot
$guid = $null; $path = $null; $backupRoot = $null
for ($i = 0; $i -lt $args.Length; $i++) {
    if ($args[$i] -eq "-guid" -and $i + 1 -lt $args.Length) { $guid = $args[$i + 1]; $i++ }
    elseif ($args[$i] -eq "-path" -and $i + 1 -lt $args.Length) { $path = $args[$i + 1]; $i++ }
    elseif ($args[$i] -eq "-backupRoot" -and $i + 1 -lt $args.Length) { $backupRoot = $args[$i + 1]; $i++ }
}

Write-Log "=============================="
Write-Log "Image Backup Script v1.0"
Write-Log "=============================="

if (-not $guid) { Write-Log "Error: -guid parameter is required"; exit 1 }
Write-Log "GUID: $guid"

# 加载 config.json 获取数据库连接参数
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Path $scriptPath -Parent
$configPath = Join-Path -Path $scriptDir -ChildPath "config.json"
if (-not (Test-Path -Path $configPath)) { Write-Log "Error: config.json not found at $configPath"; exit 1 }
try { $config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json; Write-Log "Config loaded successfully" }
catch { Write-Log "Error: Failed to parse config.json: $_"; exit 1 }
$mysqlHost = $config.backupMysql.host
$mysqlPort = $config.backupMysql.port
$mysqlUser = $config.backupMysql.user
$mysqlPassword = $config.backupMysql.password
$mysqlDatabase = $config.backupMysql.database

# 从配置读取表名（用于数据库查询）
$guidKeyTable = "rep_lot"
if ($config.tables -and $config.tables.guidKey) { $guidKeyTable = $config.tables.guidKey }

Write-Log "Database: ${mysqlHost}:${mysqlPort}/${mysqlDatabase}"

# 确定图片备份输出路径
if (-not [string]::IsNullOrEmpty($backupRoot)) {
    $baseTargetPath = Join-Path -Path $backupRoot -ChildPath "vtImages_2D\images"
    Write-Log "Using backup root: $backupRoot"
} elseif (-not [string]::IsNullOrEmpty($path)) {
    $baseTargetPath = $path
    Write-Log "Using legacy path: $path"
} else {
    $baseTargetPath = Join-Path -Path $scriptDir -ChildPath "vtImages_2D\images"
    Write-Log "Using default path: $baseTargetPath"
}

function Test-GuidValid {
    param([string]$inputGuid)
    $cleanGuid = $inputGuid.Replace('-', '')
    if ($cleanGuid.Length -ne 32) { Write-Log "Error: GUID length incorrect"; return $false }
    if ($cleanGuid -notmatch '^[0-9a-fA-F]{32}$') { Write-Log "Error: GUID contains invalid characters"; return $false }
    return $true
}

# 检查 GUID 是否在数据库中存在
function Test-GuidExistsInDB {
    param([string]$inputGuid)
    $cleanGuid = $inputGuid.Replace('-', '').ToLower()
    $query = "SELECT COUNT(*) FROM $guidKeyTable WHERE GUID = '$cleanGuid'"
    $mysqlExe = if ($mysqlBinDir) { "$mysqlBinDir\mysql.exe" } else { "mysql.exe" }
    $result = & $mysqlExe --host=$mysqlHost --port=$mysqlPort --user=$mysqlUser --password=$mysqlPassword --database=$mysqlDatabase --default-character-set=utf8mb4 -N -e $query 2>&1
    if ($LASTEXITCODE -ne 0) { 
        $errMsg = "数据库查询失败: $result"
        Write-Log "Error: $errMsg"
        Write-ErrorMsg "Error: $errMsg"
        return $false 
    }
    foreach ($line in $result) {
        if ($line -is [string] -and $line.Trim() -match '^\d+$') {
            if ([int]$line.Trim() -gt 0) { return $true }
        }
    }
    Write-Log "Error: GUID not found in database"
    Write-ErrorMsg "Error: GUID not found in database: $cleanGuid"
    return $false
}

# 清理路径中的多重反斜杠，正确处理 UNC 路径
function Clean-ImagePath {
    param([string]$rawPath)
    if ([string]::IsNullOrWhiteSpace($rawPath)) { return $rawPath }
    # 先用正则把所有连续反斜杠变成单个
    $p = $rawPath -replace '\\+', '\'
    # 如果原路径以 \ 开头（UNC 路径），恢复为双反斜杠开头
    if ($rawPath.TrimStart() -match '^\\' -and $p -match '^\\' -and -not ($p -match '^\\\\')) {
        $p = '\' + $p
    }
    return $p
}

# 图片复制主函数
# 从数据库读取 saveImgPath 字段（JSON），支持两种格式：
# 1. 嵌套格式：{"station": {"position": "path"}} - 遍历每个工位
# 2. 扁平格式：{"key": "path"} - 直接使用
function Copy-Images {
    param([string]$guid, [string]$baseTargetPath)
    $cleanGuid = $guid.Replace('-', '').ToLower()
    $guidFolder = Join-Path -Path $baseTargetPath -ChildPath $cleanGuid
    $imagesFolder = Join-Path -Path $guidFolder -ChildPath "images"
    Write-Log "Creating directory: $imagesFolder"
    if (-not (Test-Path -Path $imagesFolder)) {
        New-Item -ItemType Directory -Path $imagesFolder -Force | Out-Null
        Write-Log "Directory created successfully"
    }

    # 从数据库查询 saveImgPath JSON
    Write-Log "Querying database for saveImgPath..."
    $query = "SELECT saveImgPath FROM $guidKeyTable WHERE GUID = '$cleanGuid'"
    $mysqlExe = if ($mysqlBinDir) { "$mysqlBinDir\mysql.exe" } else { "mysql.exe" }
    $result = & $mysqlExe --host=$mysqlHost --port=$mysqlPort --user=$mysqlUser --password=$mysqlPassword --database=$mysqlDatabase --default-character-set=utf8mb4 -N -e $query 2>&1
    if ($LASTEXITCODE -ne 0) { 
        $errMsg = "数据库查询失败: $result"
        Write-Log "Error: $errMsg"
        Write-ErrorMsg "Error: $errMsg"
        return $false 
    }

    # 提取 JSON 字符串（以 { 开头的行）
    $saveImgPathJson = $null
    foreach ($line in $result) {
        if ($line -is [string] -and $line.Trim() -ne "") {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\{') { $saveImgPathJson = $trimmed; break }
        }
    }
    if ([string]::IsNullOrEmpty($saveImgPathJson)) {
        Write-Log "Warning: No saveImgPath data found for this GUID"
        return $true
    }

    # 解析 JSON
    try { $saveImgPathObj = $saveImgPathJson | ConvertFrom-Json; Write-Log "JSON parsed successfully" }
    catch { 
        $errMsg = "JSON 解析失败: $_"
        Write-Log "Warning: $errMsg"
        Write-ErrorMsg "Error: $errMsg"
        return $true 
    }

    $workstationCount = ($saveImgPathObj.PSObject.Properties | Measure-Object).Count
    Write-Log "Found $workstationCount workstation(s) to process"
    if ($workstationCount -eq 0) { Write-Log "No image paths found"; return $true }

    # 遍历每个工作站，处理嵌套和扁平两种 JSON 格式
    $stationIndex = 1
    $successCount = 0
    $failedCount = 0
    $failedDetails = New-Object System.Collections.ArrayList

    foreach ($stationProp in $saveImgPathObj.PSObject.Properties) {
        $stationName = $stationProp.Name
        $stationValue = $stationProp.Value
        Write-Log "`nProcessing workstation $stationIndex : $stationName"

        # 嵌套格式：值是对象，包含多个工位
        if ($stationValue -is [System.Management.Automation.PSCustomObject]) {
            foreach ($positionProp in $stationValue.PSObject.Properties) {
                $positionName = $positionProp.Name
                $imagePath = $positionProp.Value.ToString()
                $cleanPath = Clean-ImagePath $imagePath
                Write-Log "  Position: $positionName, Path: $cleanPath"
                if ([string]::IsNullOrEmpty($cleanPath)) { 
                    Write-Log "  Warning: empty path, skipping"
                    [void]$failedDetails.Add("[$stationName/$positionName] 路径为空")
                    $failedCount++
                    continue 
                }
                $stationFolder = Join-Path -Path $imagesFolder -ChildPath "station_" | Join-Path -ChildPath $positionName
                if (Test-Path -Path $cleanPath -PathType Container) {
                    Write-Log "  Source exists, copying..."
                    if (-not (Test-Path $stationFolder)) { New-Item -ItemType Directory -Path $stationFolder -Force | Out-Null }
                    & robocopy $cleanPath $stationFolder /E /R:0 /W:0 /NDL /NFL /NJH /NJS
                    if ($LASTEXITCODE -le 3) { Write-Log "  OK: $positionName"; $successCount++ }
                    else { 
                        Write-Log "  Error: robocopy exit $LASTEXITCODE"
                        [void]$failedDetails.Add("[$stationName/$positionName] robocopy 失败 (exit $LASTEXITCODE) 源路径: $cleanPath")
                        $failedCount++ 
                    }
                } else { 
                    Write-Log "  Warning: source not found: $cleanPath"
                    [void]$failedDetails.Add("[$stationName/$positionName] 源路径不存在: $cleanPath")
                    $failedCount++ 
                }
            }
        }
        # 扁平格式：值是字符串
        else {
            $imagePath = $stationValue.ToString()
            $cleanPath = $imagePath.Replace('\\', '\\').Replace('\\', '\\')
            Write-Log "  Path: $cleanPath"
            $stationFolder = Join-Path -Path $imagesFolder -ChildPath "station_"
            if ([string]::IsNullOrEmpty($cleanPath)) { Write-Log "  Warning: empty path, skipping"; $failedCount++ }
            elseif (Test-Path -Path $cleanPath -PathType Container) {
                Write-Log "  Source exists, copying..."
                if (-not (Test-Path $stationFolder)) { New-Item -ItemType Directory -Path $stationFolder -Force | Out-Null }
                & robocopy $cleanPath $stationFolder /E /R:0 /W:0 /NDL /NFL /NJH /NJS
                if ($LASTEXITCODE -le 3) { Write-Log "  OK: $stationName"; $successCount++ }
                else { Write-Log "  Error: robocopy exit $LASTEXITCODE"; $failedCount++ }
            } else { Write-Log "  Warning: source not found: $cleanPath"; $failedCount++ }
        }
        $stationIndex++
    }

    Write-Log "`n=============================="
    Write-Log "Image backup completed"
    Write-Log "Processed: $($stationIndex-1) workstation(s)"
    Write-Log "Successful: $successCount"
    Write-Log "Failed: $failedCount"
    Write-Log "=============================="

    if ($failedCount -gt 0) { return $false }
    return $true
}

# 主执行流程
Write-Log "`nStep 1: Validating GUID..."
if (-not (Test-GuidValid -inputGuid $guid)) { Write-Log "Error: Invalid GUID format"; exit 1 }

Write-Log "Step 2: Checking GUID in database..."
if (-not (Test-GuidExistsInDB -inputGuid $guid)) { Write-Log "Error: GUID not found in database"; exit 1 }

Write-Log "Step 3: Copying images..."
if (-not (Copy-Images -guid $guid -baseTargetPath $baseTargetPath)) { Write-Log "Error: Image copy failed"; exit 1 }

Write-Log "`nImage backup completed successfully!"
exit 0