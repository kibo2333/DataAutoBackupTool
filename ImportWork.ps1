try {
    [System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [System.Console]::InputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$PSDefaultParameterValues['*:Encoding'] = 'UTF8'

function Write-Log {
    param([string]$message)
    [Console]::WriteLine($message)
}

function Find-MySqlBin {
    $cmd = Get-Command "mysql.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        return Split-Path $cmd.Source
    }

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
    return $null
}

$mysqlBinDir = Find-MySqlBin
if ($mysqlBinDir) {
    $env:PATH = "$mysqlBinDir;$env:PATH"
    Write-Log "MySQL bin: $mysqlBinDir"
} else {
    Write-Log "Warning: MySQL not found in PATH"
}

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
        "--execute=START TRANSACTION; DELETE FROM rep_lot WHERE GUID='$guidToDelete'; DELETE FROM rep_frame WHERE GUID LIKE '$guidToDelete%'; DELETE FROM rep_result WHERE GUID LIKE '$guidToDelete%'; DELETE FROM rep_unit WHERE GUID LIKE '$guidToDelete%'; DELETE FROM sys_defect WHERE GUID LIKE '$guidToDelete%'; DELETE FROM sys_unit WHERE GUID LIKE '$guidToDelete%'; COMMIT;"
    )

    $output = & mysql $argsList 2>&1
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
        "--execute=SET FOREIGN_KEY_CHECKS=0; TRUNCATE TABLE rep_lot; TRUNCATE TABLE rep_frame; TRUNCATE TABLE rep_result; TRUNCATE TABLE rep_unit; TRUNCATE TABLE sys_defect; TRUNCATE TABLE sys_unit; SET FOREIGN_KEY_CHECKS=1;"
    )

    $output = & mysql $argsList 2>&1
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

$successCount = 0
$failedFiles = @()
$errorMessages = @()

if ($duplicateOption -eq "清空后导入") {
    if (-not (TruncateAllTables)) {
        Write-Log "[ERROR] Truncate failed, import aborted"
        exit 1
    }
}

if ($duplicateOption -eq "覆盖重复") {
    Write-Log "[INFO] Overwrite mode: delete existing data first"
    if (-not (DeleteExistingGuidData -guidToDelete $guid)) {
        Write-Log "[ERROR] Delete failed, import aborted"
        exit 1
    }
}

foreach ($sqlFile in $sqlFiles) {
    Write-Log "[PROCESS] Importing: $($sqlFile.Name)"

    try {
        $argsList = @(
            "--host=$mysqlHost",
            "--port=$mysqlPort",
            "--user=$mysqlUser",
            "--password=$mysqlPassword",
            "--database=$mysqlDatabase",
            "--default-character-set=utf8mb4"
        )

        $filePath = $sqlFile.FullName
        $mysqlExe = if ($mysqlBinDir) { "$mysqlBinDir\mysql.exe" } else { "mysql.exe" }
        $importArgs = $argsList.Clone(); $importArgs += @("--execute=SET NAMES utf8mb4; SOURCE `"$filePath`";")

        Write-Log "[DEBUG] Executing: $mysqlExe $($importArgs -join ' ')"
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $mysqlExe
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
            foreach ($a in $importArgs) { $psi.ArgumentList.Add($a) }
            $proc = [System.Diagnostics.Process]::Start($psi)
            $output = $proc.StandardOutput.ReadToEnd()
            $errOut = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()
            $LASTEXITCODE = $proc.ExitCode
            if (-not [string]::IsNullOrEmpty($errOut)) { $output = $errOut }
        } catch {
            $output = "Exception: $_"
            $LASTEXITCODE = 1
        }
        foreach ($line in $output) {
            if ($line -notlike "*Using a password*") {
                if ($line -like "*ERROR*" -or $line -like "*error*") {
                    Write-Log "[ERROR] $line"
                } else {
                    Write-Log "[MYSQL] $line"
                }
            }
        }

        if ($LASTEXITCODE -ne 0) {
            $errorMsg = "Failed to import $($sqlFile.Name) (ExitCode: $LASTEXITCODE)"
            Write-Log "[ERROR] $errorMsg"
            $failedFiles += $sqlFile.Name
            $errorMessages += $errorMsg
        } else {
            Write-Log "[SUCCESS] Imported: $($sqlFile.Name)"
            $successCount++
        }
    } catch {
        $errorMsg = "Exception importing $($sqlFile.Name): $_"
        Write-Log "[EXCEPTION] $errorMsg"
        $failedFiles += $sqlFile.Name
        $errorMessages += $errorMsg
    }
}

Write-Log ""
Write-Log "[Step 2] Import completed!"
Write-Log "[RESULT] Successfully imported $successCount files"

if ($failedFiles.Count -gt 0) {
    Write-Log "[RESULT] Failed: $($failedFiles.Count) files"
    foreach ($file in $failedFiles) {
        Write-Log "[FAILED] - $file"
    }
    foreach ($msg in $errorMessages) {
        Write-Log "[ERROR] $msg"
    }
    exit 1
}

Write-Log "[SUCCESS] All data imported successfully!"
exit 0
