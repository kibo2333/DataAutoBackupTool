# 公共模块：UTF-8 编码、MySQL 查找、通用日志
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'UTF8'
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Log {
    param([string]$message)
    # ponytail: 不用 [Console]::WriteLine —— CreateNoWindow + 重定向 stdout 时，
    # .NET Framework 访问控制台句柄可能挂起数分钟。
    # 用 Write-Output 写入 stdout 流，C# 端通过 BeginOutputReadLine 捕获。
    Write-Output $message
}

function Find-MySqlBin {
    $cmd = Get-Command "mysql.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path $cmd.Source }
    $services = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services" -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match "^MySQL" }
    foreach ($svc in $services) {
        $imgPath = (Get-ItemProperty $svc.PSPath -ErrorAction SilentlyContinue).ImagePath
        if ($imgPath) {
            $binDir = Split-Path ($imgPath -replace '"', '').Trim()
            if ($binDir -and (Test-Path (Join-Path $binDir "mysql.exe"))) { return $binDir }
        }
    }
    $fixedPaths = @("E:\MySQL\MySQL Server 8.0\bin", "D:\MySQL\MySQL Server 8.0\bin")
    foreach ($fixedPath in $fixedPaths) {
        if (Test-Path (Join-Path $fixedPath "mysql.exe")) { return $fixedPath }
    }
    return $null
}
