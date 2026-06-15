# -*- coding: utf-8 -*-



[Console]::OutputEncoding = [System.Text.Encoding]::UTF8



[Console]::InputEncoding = [System.Text.Encoding]::UTF8



$PSDefaultParameterValues['*:Encoding'] = 'UTF8'



$OutputEncoding = [System.Text.Encoding]::UTF8







# 日志输出函数



function Write-Log { param([string]$message); [Console]::WriteLine($message) }







# 查找 MySQL 可执行文件路径：优先 PATH，其次读 Windows 服务注册表



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



if ($mysqlBinDir) { $env:PATH = "$mysqlBinDir;$env:PATH"; Write-Log "MySQL bin: $mysqlBinDir" }



else { Write-Log "Warning: MySQL not found in PATH" }







# 手动解析参数：-guid / -path / -backupRoot



for ($i = 0; $i -lt $args.Length; $i++) {



    if ($args[$i] -eq "-guid" -and $i + 1 -lt $args.Length) { $guid = $args[$i + 1]; $i++ }



    elseif ($args[$i] -eq "-path" -and $i + 1 -lt $args.Length) { $path = $args[$i + 1]; $i++ }



    elseif ($args[$i] -eq "-backupRoot" -and $i + 1 -lt $args.Length) { $backupRoot = $args[$i + 1]; $i++ }



}







# 校验 GUID 格式：32位十六进制



function Test-GuidValid {



    param([string]$inputGuid)



    $cleanGuid = $inputGuid.Replace('-', '')



    return ($cleanGuid.Length -eq 32 -and $cleanGuid -match '^[0-9a-fA-F]{32}$')



}







# 检查 GUID 是否存在于数据库



function Test-GuidExistsInDB {



    param([string]$inputGuid)



    $cleanGuid = $inputGuid.Replace('-', '').ToLower()



    $query = "SELECT COUNT(*) FROM rep_lot WHERE GUID = '$cleanGuid'"



    $mysqlExe = if ($mysqlBinDir) { "$mysqlBinDir\mysql.exe" } else { "mysql.exe" }

    $result = & $mysqlExe --host=$mysqlHost --port=$mysqlPort --user=$mysqlUser --password=$mysqlPassword --database=$mysqlDatabase --default-character-set=utf8mb4 -N -e $query 2>&1



    if ($LASTEXITCODE -ne 0) { Write-Log "Error: Database query failed"; return $false }



    foreach ($line in $result) {



        if ($line -is [string] -and $line.Trim() -match '^\d+$') {



            if ([int]$line.Trim() -gt 0) { return $true }



        }



    }



    Write-Log "Error: GUID not found in database"



    return $false



}







# 获取 detectionsSHA256，用于 rep_detections 表导出条件



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







# 导出单张表数据为 SQL 文件



# rep_detections 按 detectionsSHA256 筛导，sys_defect 导出全部，其余按 GUID 筛导



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

        $psi.Arguments = $argsList

        $psi.RedirectStandardOutput = $true

        $psi.RedirectStandardError = $true

        $psi.UseShellExecute = $false

        $process = [System.Diagnostics.Process]::Start($psi)

        $stdOut = $process.StandardOutput.ReadToEnd()

        $stdErr = $process.StandardError.ReadToEnd()

        $process.WaitForExit()

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







if (-not (Test-GuidExistsInDB -inputGuid $cleanGuid)) { Write-Log "Error: GUID not in database"; exit 1 }







# 确定输出目录



if (-not [string]::IsNullOrEmpty($backupRoot)) { $baseTargetPath = Join-Path $backupRoot "data"; Write-Log "Backup root: $backupRoot" }



elseif (-not [string]::IsNullOrEmpty($path)) { $baseTargetPath = $path; Write-Log "Path: $path" }



else { $baseTargetPath = if (-not [string]::IsNullOrEmpty($config.paths.dataBackupPath)) { $config.paths.dataBackupPath } else { "data" } }







$guidDir = Join-Path -Path $baseTargetPath -ChildPath $cleanGuid



if (-not (Test-Path -Path $guidDir)) { try { New-Item -ItemType Directory -Path $guidDir -Force | Out-Null } catch { Write-Log "Error: mkdir failed"; exit 1 } }



Write-Log "Output: $guidDir"







Write-Log "`n[Step 1] Query detectionsSHA256..."



$detectionsSHA256 = Get-DetectionsSHA256 -guid $cleanGuid



if (-not [string]::IsNullOrEmpty($detectionsSHA256)) { Write-Log "detectionsSHA256: $detectionsSHA256" }



else { Write-Log "Warning: detectionsSHA256 empty, skip rep_detections" }







$tables = @("rep_lot", "rep_frame", "rep_unit", "rep_result", "rep_detections", "sys_defect")



$exportedFiles = @(); $failedTables = @()







Write-Log "`n[Step 2] Exporting table data..."



foreach ($table in $tables) {



    $outputFile = "${table}_data.sql"



    $fullPath = Join-Path -Path $guidDir -ChildPath $outputFile



    if (Export-TableData -tableName $table -guid $cleanGuid -detectionsSHA256 $detectionsSHA256 -outputDir $guidDir) {



        if (Test-Path -Path $fullPath) { $exportedFiles += $outputFile }



    } else { $failedTables += $table }



}







Write-Log "`n[Step 3] Export complete!"



Write-Log "Exported: $($exportedFiles -join ', ')"



if ($failedTables.Count -gt 0) { Write-Log "Failed: $($failedTables -join ', ')"; exit 1 }



Write-Log "`nTable data export succeeded!"



exit 0



