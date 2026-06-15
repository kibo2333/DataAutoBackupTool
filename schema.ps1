# -*- coding: utf-8 -*-
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'UTF8'
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Log {
    param([string]$message)
    [Console]::WriteLine($message)
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
            $binDir = Split-Path ($imgPath -replace '"','').Trim()
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
if ($mysqlBinDir) { $env:PATH = "$mysqlBinDir;$env:PATH"; Write-Log "MySQL bin: $mysqlBinDir" }
else { Write-Log "Warning: MySQL not found in PATH" }

$guid = $null
$path = $null

for ($i = 0; $i -lt $args.Length; $i++) {
    if ($args[$i] -eq "-guid" -and $i + 1 -lt $args.Length) { $guid = $args[$i + 1]; $i++ }
    elseif ($args[$i] -eq "-path" -and $i + 1 -lt $args.Length) { $path = $args[$i + 1]; $i++ }
}

function Test-GuidValid {
    param([string]$inputGuid)
    $cleanGuid = $inputGuid.Replace('-', '')
    return ($cleanGuid.Length -eq 32 -and $cleanGuid -match '^[0-9a-fA-F]{32}$')
}

# 使用 mysqldump --no-data 导出表结构（不含数据）
function Export-TableSchema {
    param(
        [string[]]$tables, [string]$outputDir,
        [string]$mysqlHost, [string]$mysqlPort,
        [string]$mysqlUser, [string]$mysqlPassword, [string]$mysqlDatabase
    )
    Write-Log "Exporting table schemas to: $outputDir"
    $successCount = 0
    $failedTables = @()
    foreach ($table in $tables) {
        Write-Log "
Processing: $table"
        $outputFile = Join-Path -Path $outputDir -ChildPath "${table}_schema.sql"
        if (Test-Path $outputFile) { Remove-Item -Path $outputFile -ErrorAction SilentlyContinue }
        $argsList = @(
            "--host=$mysqlHost", "--port=$mysqlPort", "--user=$mysqlUser",
            "--password=$mysqlPassword", "--no-data", "--default-character-set=utf8mb4",
            $mysqlDatabase, $table
        )
        try {
            $mysqldumpExe = if ($mysqlBinDir) { "$mysqlBinDir\mysqldump.exe" } else { "mysqldump.exe" }
            $output = & $mysqldumpExe @argsList 2>&1
            if ($LASTEXITCODE -eq 0) {
                $sqlContent = $output | Where-Object { $_ -notlike "*Using a password on the command line interface can be insecure*" }
                [System.IO.File]::WriteAllBytes($outputFile, [System.Text.Encoding]::UTF8.GetBytes($( $sqlContent -join "
" )))
                Write-Log "OK: $table"
                $successCount++
            } else {
                Write-Log "Failed: $table - $output"
                $failedTables += $table
            }
        } catch {
            Write-Log "Exception: $table - $_"
            $failedTables += $table
        }
    }
    Write-Log "
Done! Success: $successCount, Failed: $($failedTables.Count)"
    if ($failedTables.Count -gt 0) { Write-Log "Failed: $( $failedTables -join ', ' )" }
    return $failedTables.Count -eq 0
}

Write-Log "=============================="
Write-Log "Table Schema Export Script v1.0"
Write-Log "=============================="

if (-not $guid) { Write-Log "Error: -guid parameter required"; exit 1 }
if (-not (Test-GuidValid -inputGuid $guid)) { Write-Log "Error: Invalid GUID format"; exit 1 }

$cleanGuid = $guid.Replace('-', '').ToLower()
Write-Log "
GUID: $cleanGuid"

if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent }
$configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"
if (-not (Test-Path -Path $configPath)) { Write-Log "Error: config.json not found"; exit 1 }

$config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$mysqlHost = $config.backupMysql.host
$mysqlPort = $config.backupMysql.port
$mysqlUser = $config.backupMysql.user
$mysqlPassword = $config.backupMysql.password
$mysqlDatabase = $config.backupMysql.database

# 确定 schema 输出目录
if (-not [string]::IsNullOrEmpty($path)) { $baseTargetPath = $path }
else { $baseTargetPath = $config.paths.baseTargetPath }

$schemaDir = Join-Path -Path $baseTargetPath -ChildPath "schema\$cleanGuid"
if (-not (Test-Path -Path $schemaDir)) { New-Item -ItemType Directory -Path $schemaDir -Force | Out-Null }

# 导出 6 张表的结构
$tables = @("rep_lot", "rep_frame", "rep_unit", "rep_result", "rep_detections", "sys_defect")
$success = Export-TableSchema -tables $tables -outputDir $schemaDir -mysqlHost $mysqlHost -mysqlPort $mysqlPort -mysqlUser $mysqlUser -mysqlPassword $mysqlPassword -mysqlDatabase $mysqlDatabase

if (-not $success) { exit 1 }
exit 0