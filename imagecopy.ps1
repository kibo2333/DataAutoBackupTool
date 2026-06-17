. "$PSScriptRoot\_common.ps1"

$mysqlBinDir = Find-MySqlBin
if ($mysqlBinDir) { $env:PATH = "$mysqlBinDir;$env:PATH"; Write-Log "MySQL bin: $mysqlBinDir" }
else { Write-Log "Warning: MySQL not found in PATH" }

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

$guidKeyTable = "rep_lot"
if ($config.tables -and $config.tables.guidKey) { $guidKeyTable = $config.tables.guidKey }

Write-Log "Database: ${mysqlHost}:${mysqlPort}/${mysqlDatabase}"

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

function Test-GuidExistsInDB {
    param([string]$inputGuid)
    $cleanGuid = $inputGuid.Replace('-', '').ToLower()
    $query = "SELECT COUNT(*) FROM $guidKeyTable WHERE GUID = '$cleanGuid'"
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
    Write-Log "Querying database for saveImgPath..."
    $query = "SELECT saveImgPath FROM $guidKeyTable WHERE GUID = '$cleanGuid'"
    $mysqlExe = if ($mysqlBinDir) { "$mysqlBinDir\mysql.exe" } else { "mysql.exe" }
    $result = & $mysqlExe --host=$mysqlHost --port=$mysqlPort --user=$mysqlUser --password=$mysqlPassword --database=$mysqlDatabase --default-character-set=utf8mb4 -N -e $query 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Log "Error: Database query failed: $result"; return $false }
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
    try { $saveImgPathObj = $saveImgPathJson | ConvertFrom-Json; Write-Log "JSON parsed successfully" }
    catch { Write-Log "Warning: Failed to parse JSON: $_"; return $true }
    $workstationCount = ($saveImgPathObj.PSObject.Properties | Measure-Object).Count
    Write-Log "Found $workstationCount workstation(s) to process"
    if ($workstationCount -eq 0) { Write-Log "No image paths found"; return $true }
    $stationIndex = 1
    $successCount = 0
    $failedCount = 0
    foreach ($stationProp in $saveImgPathObj.PSObject.Properties) {
        $stationName = $stationProp.Name
        $stationValue = $stationProp.Value
        Write-Log "Processing workstation $stationIndex : $stationName"
        if ($stationValue -is [System.Management.Automation.PSCustomObject]) {
            foreach ($positionProp in $stationValue.PSObject.Properties) {
                $positionName = $positionProp.Name
                $imagePath = $positionProp.Value.ToString()
                $cleanPath = $imagePath -replace '\\\\', '\'
                Write-Log "  Position: $positionName, Path: $cleanPath"
                if ([string]::IsNullOrEmpty($cleanPath)) { Write-Log "  Warning: empty path, skipping"; $failedCount++; continue }
                $stationFolder = Join-Path -Path $imagesFolder -ChildPath "station_" | Join-Path -ChildPath $positionName
                if (Test-Path -Path $cleanPath -PathType Container) {
                    Write-Log "  Source exists, copying..."
                    if (-not (Test-Path $stationFolder)) { New-Item -ItemType Directory -Path $stationFolder -Force | Out-Null }
                    & robocopy $cleanPath $stationFolder /E /R:0 /W:0 /NDL /NFL /NJH /NJS
                    if ($LASTEXITCODE -le 3) { Write-Log "  OK: $positionName"; $successCount++ }
                    else { Write-Log "  Error: robocopy exit $LASTEXITCODE"; $failedCount++ }
                } else { Write-Log "  Warning: source not found: $cleanPath"; $failedCount++ }
            }
        } else {
            $imagePath = $stationValue.ToString()
            $cleanPath = $imagePath -replace '\\\\', '\'
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
    Write-Log "Image backup completed"
    Write-Log "Processed: $($stationIndex-1) workstation(s)"
    Write-Log "Successful: $successCount"
    Write-Log "Failed: $failedCount"
    if ($failedCount -gt 0) { return $false }
    return $true
}

Write-Log "Step 1: Validating GUID..."
if (-not (Test-GuidValid -inputGuid $guid)) { Write-Log "Error: Invalid GUID format"; exit 1 }
Write-Log "Step 2: Checking GUID in database..."
if (-not (Test-GuidExistsInDB -inputGuid $guid)) { Write-Log "Error: GUID not found in database"; exit 1 }
Write-Log "Step 3: Copying images..."
if (-not (Copy-Images -guid $guid -baseTargetPath $baseTargetPath)) { Write-Log "Error: Image copy failed"; exit 1 }
Write-Log "Image backup completed successfully!"
exit 0
