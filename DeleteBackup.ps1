. "$PSScriptRoot\_common.ps1"

$mysqlBinDir = Find-MySqlBin
if ($mysqlBinDir) { $env:PATH = "$mysqlBinDir;$env:PATH" }

$guid = $null
$path = $null

for ($i = 0; $i -lt $args.Length; $i++) {
    if ($args[$i] -eq "-guid" -and $i + 1 -lt $args.Length) { $guid = $args[$i + 1]; $i++ }
    elseif ($args[$i] -eq "-path" -and $i + 1 -lt $args.Length) { $path = $args[$i + 1]; $i++ }
}

if (-not $guid) { Write-Log "Error: -guid parameter required"; exit 1 }
$cleanGuid = $guid.Replace('-', '').ToLower()
if ($cleanGuid.Length -ne 32 -or $cleanGuid -notmatch '^[0-9a-fA-F]{32}$') { Write-Log "Error: Invalid GUID format"; exit 1 }

$repoRoot = $PSScriptRoot
$configPath = Join-Path $repoRoot "config.json"
if (-not (Test-Path $configPath)) { Write-Log "Error: config.json not found"; exit 1 }
try { $config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Write-Log "Error: Failed to parse config.json - $_"; exit 1 }

$mysqlHost = $config.backupMysql.host
$mysqlport = $config.backupMysql.port
$mysqlUser = $config.backupMysql.user
$mysqlPassword = $config.backupMysql.password
$mysqlDatabase = $config.backupMysql.database

if (-not [string]::IsNullOrEmpty($path)) {
    $backupRoot = $path.TrimEnd('\')
} else {
    $backupRoot = $repoRoot
    if ($config.ui -and $config.ui.backupRoot) {
        $rootVal = $config.ui.backupRoot.Trim()
        if (-not [string]::IsNullOrEmpty($rootVal)) { $backupRoot = $rootVal }
    }
}

Write-Log "=============================="
Write-Log "Delete Backup Files v1.0"
Write-Log "=============================="
Write-Log "GUID: $cleanGuid"
Write-Log "Backup Root: $backupRoot"

$guidImagesFolder = Join-Path $backupRoot "vtImages_2D\images\$cleanGuid"
$guidDataFolder = Join-Path $backupRoot "data\$cleanGuid"
$guidSchemaFolder = Join-Path $backupRoot "schema\$cleanGuid"

$deletedFolders = 0
$failedFolders = 0

foreach ($folder in @($guidImagesFolder, $guidDataFolder, $guidSchemaFolder)) {
    if (Test-Path $folder) {
        try {
            Remove-Item -Path $folder -Recurse -Force
            Write-Log "Deleted: $folder"
            $deletedFolders++
        } catch {
            Write-Log "Failed to delete: $folder - $_"
            $failedFolders++
        }
    } else {
        Write-Log "Not found (no action needed): $folder"
    }
}

$recordsPath = Join-Path $repoRoot "backup_records.json"
if (Test-Path $recordsPath) {
    try {
        $records = Get-Content -Path $recordsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($records -ne $null -and $records -is [System.Array]) {
            $originalCount = $records.Count
            $records = $records | Where-Object { $_.GUID -ne $cleanGuid -and $_.GUID -ne $guid }
            $newCount = if ($records -is [System.Array]) { $records.Count } elseif ($records -eq $null) { 0 } else { 1 }
            if ($originalCount -ne $newCount) {
                $records | ConvertTo-Json -Depth 10 | Set-Content -Path $recordsPath -Encoding UTF8
                Write-Log "Removed $($originalCount - $newCount) record(s) from backup_records.json"
            }
        }
    } catch {
        Write-Log "Failed to update backup_records.json: $_"
    }
}

Write-Log "Delete completed: $deletedFolders deleted, $failedFolders failed"
if ($failedFolders -gt 0) { exit 1 }
exit 0
