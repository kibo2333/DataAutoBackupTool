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

function Test-GuidExistsInDB {
    param([string]$inputGuid)
    $cleanGuid = $inputGuid.Replace('-', '').ToLower()
    $query = "SELECT COUNT(*) FROM rep_lot WHERE GUID = '$cleanGuid'"
    $mysqlExe = if ($mysqlBinDir) { "$mysqlBinDir\mysql.exe" } else { "mysql.exe" }
    $result = & $mysqlExe --host=$mysqlHost --port=$mysqlPort --user=$mysqlUser --password=$mysqlPassword --database=$mysqlDatabase --default-character-set=utf8mb4 -N -e $query 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Log "Warning: Database query failed for GUID check"; return $false }
    foreach ($line in $result) {
        if ($line -is [string] -and $line.Trim() -match '^\d+$') {
            if ([int]$line.Trim() -gt 0) { return $true }
        }
    }
    return $false
}

function Get-DetectionsSHA256 {
    param([string]$guid)
    $query = "SELECT detectionsSHA256 FROM rep_lot WHERE GUID = '$guid';"
    $mysqlExe = if ($mysqlBinDir) { "$mysqlBinDir\mysql.exe" } else { "mysql.exe" }
    $result = & $mysqlExe --host=$mysqlHost --port=$mysqlPort --user=$mysqlUser --password=$mysqlPassword --database=$mysqlDatabase --default-character-set=utf8mb4 -N -e $query 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Log "Error: Failed to query detectionsSHA256"; return $null }
    if ([string]::IsNullOrEmpty($result) -or $result -match '^NULL$') { return $null }
    $firstLine = $result[0]
    if ($firstLine -is [string]) { return $firstLine.Trim() }
    return $null
}

function Export-TableData {
    param([string]$tableName, [string]$guid, [string]$detectionsSHA256, [string]$outputDir)
    $outputFile = Join-Path -Path $outputDir -ChildPath "${tableName}_data.sql"
    Write-Log "Exporting table: $tableName"
    switch ($tableName) {
        "rep_detections" {
            if ([string]::IsNullOrEmpty($detectionsSHA256)) { Write-Log "Warning: detectionsSHA256 empty, skipping"; return $true }
            $whereClause = "recipeSHA256 = '$detectionsSHA256'"
        }
        "sys_defect" { $whereClause = $null }
        default { $whereClause = "GUID = '$guid'" }
    }
    $argsList = @("--host=$mysqlHost", "--port=$mysqlPort", "--user=$mysqlUser", "--password=$mysqlPassword", "--single-transaction", "--complete-insert", "--no-create-info", "--default-character-set=utf8mb4", $mysqlDatabase, $tableName)
    if ($whereClause) { $argsList += "--where=`"$whereClause`"" }
    try {
        $mysqldumpExe = if ($mysqlBinDir) { "$mysqlBinDir\mysqldump.exe" } else { "mysqldump.exe" }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $mysqldumpExe
        $psi.Arguments = $argsList -join ' '
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $process = [System.Diagnostics.Process]::Start($psi)
        # ponytail: 先异步读 stderr（小数据量），再同步读 stdout，防止管道死锁
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $stdOut = $process.StandardOutput.ReadToEnd()
        if (-not $process.WaitForExit(300000)) {
            $process.Kill()
            $process.WaitForExit(5000)
            Write-Log "Error: mysqldump timed out for $tableName"
            return $false
        }
        $stdErr = $stderrTask.GetAwaiter().GetResult()
        [System.IO.File]::WriteAllText($outputFile, $stdOut, [System.Text.Encoding]::UTF8)
        if ($process.ExitCode -ne 0) { Write-Log "Error: Failed to export $tableName"; if (-not [string]::IsNullOrEmpty($stdErr)) { Write-Log "stderr: $stdErr" }; return $false }
        if (-not (Test-Path $outputFile) -or (Get-Content -Path $outputFile -Raw -Encoding UTF8).Length -eq 0) { Write-Log "Warning: No data for $tableName"; Remove-Item -Path $outputFile -ErrorAction SilentlyContinue; return $true }
        Write-Log "Exported: $outputFile"
        return $true
    }
    catch { Write-Log "Error: mysqldump failed - $_"; return $false }
}

Write-Log "=============================="
Write-Log "Table Data Export Script v1.0"
Write-Log "=============================="

if (-not $guid) { Write-Log "Error: -guid parameter required"; exit 1 }
if (-not (Test-GuidValid -inputGuid $guid)) { Write-Log "Error: Invalid GUID format"; exit 1 }
$cleanGuid = $guid.Replace('-', '').ToLower()
Write-Log "`nGUID: $cleanGuid"

if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent }
$configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"
if (-not (Test-Path -Path $configPath)) { Write-Log "Error: config.json not found"; exit 1 }
$config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $config -or -not $config.backupMysql) { Write-Log "Error: config.json invalid"; exit 1 }
$mysqlHost = $config.backupMysql.host
$mysqlPort = $config.backupMysql.port
$mysqlUser = $config.backupMysql.user
$mysqlPassword = $config.backupMysql.password
$mysqlDatabase = $config.backupMysql.database

if (-not [string]::IsNullOrEmpty($path)) { $baseTargetPath = $path }
else { $baseTargetPath = $config.paths.baseTargetPath }
$guidDir = Join-Path -Path $baseTargetPath -ChildPath $cleanGuid
if (-not (Test-Path -Path $guidDir)) { New-Item -ItemType Directory -Path $guidDir -Force | Out-Null }

Write-Log "`nQuerying detectionsSHA256..."
$detectionsSHA256 = Get-DetectionsSHA256 -guid $cleanGuid
if ($detectionsSHA256) { Write-Log "detectionsSHA256: $detectionsSHA256" }
else { Write-Log "detectionsSHA256: (null)" }

Write-Log "`nExporting table data..."
$tables = @("rep_lot", "rep_frame", "rep_unit", "rep_result", "rep_detections", "sys_defect")
$successCount = 0
$failedTables = @()
foreach ($table in $tables) {
    if (Export-TableData -tableName $table -guid $cleanGuid -detectionsSHA256 $detectionsSHA256 -outputDir $guidDir) { $successCount++ }
    else { $failedTables += $table }
}

Write-Log "`nDone! Success: $successCount, Failed: $($failedTables.Count)"
if ($failedTables.Count -gt 0) { Write-Log "Failed: $($failedTables -join ', ')"; exit 1 }
Write-Log "All data exported successfully!"
exit 0
