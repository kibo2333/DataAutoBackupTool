. "$PSScriptRoot\_common.ps1"

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
        Write-Log "Processing: $table"
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
                $sqlText = $sqlContent -join "`r`n"
                [System.IO.File]::WriteAllText($outputFile, $sqlText, [System.Text.Encoding]::UTF8)
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
    Write-Log "Done! Success: $successCount, Failed: $($failedTables.Count)"
    if ($failedTables.Count -gt 0) { Write-Log "Failed: $( $failedTables -join ', ' )" }
    return $failedTables.Count -eq 0
}

Write-Log "=============================="
Write-Log "Table Schema Export Script v1.0"
Write-Log "=============================="

if (-not $guid) { Write-Log "Error: -guid parameter required"; exit 1 }
if (-not (Test-GuidValid -inputGuid $guid)) { Write-Log "Error: Invalid GUID format"; exit 1 }

$cleanGuid = $guid.Replace('-', '').ToLower()
Write-Log "GUID: $cleanGuid"

if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent }
$configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"
if (-not (Test-Path -Path $configPath)) { Write-Log "Error: config.json not found"; exit 1 }

$config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$mysqlHost = $config.backupMysql.host
$mysqlPort = $config.backupMysql.port
$mysqlUser = $config.backupMysql.user
$mysqlPassword = $config.backupMysql.password
$mysqlDatabase = $config.backupMysql.database

if (-not [string]::IsNullOrEmpty($path)) { $baseTargetPath = $path }
else { $baseTargetPath = $config.paths.baseTargetPath }

$schemaDir = Join-Path -Path $baseTargetPath -ChildPath "schema\$cleanGuid"
if (-not (Test-Path -Path $schemaDir)) { New-Item -ItemType Directory -Path $schemaDir -Force | Out-Null }

$tables = @("rep_lot", "rep_frame", "rep_unit", "rep_result", "rep_detections", "sys_defect")
$success = Export-TableSchema -tables $tables -outputDir $schemaDir -mysqlHost $mysqlHost -mysqlPort $mysqlPort -mysqlUser $mysqlUser -mysqlPassword $mysqlPassword -mysqlDatabase $mysqlDatabase

if (-not $success) { exit 1 }
exit 0
