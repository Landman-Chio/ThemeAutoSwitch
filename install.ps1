param(
    [switch]$NoAutostart,
    [string]$Dir = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Dir) { $Dir = Split-Path -Parent $MyInvocation.MyCommand.Path }

$ps1 = Join-Path $Dir 'ThemeAutoSwitch.ps1'
$vbs = Join-Path $Dir 'launcher.vbs'
foreach ($p in @($ps1, $vbs)) { if (-not (Test-Path $p)) { throw "缺少文件: $p" } }

# 1) 先按当前时间切一次, 避免刚启动时状态不对
Write-Output '--- 按当前时间应用一次 ---'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 -Action apply

# 2) 结束已在运行的实例, 避免重复常驻
$me = $PID
$running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -match 'ThemeAutoSwitch\.ps1' -and $_.CommandLine -notmatch 'Get-CimInstance' }
foreach ($p in $running) {
    Write-Output ("结束已有实例 PID {0}" -f $p.ProcessId)
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1

# 3) 静默启动常驻
Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$vbs`""
Start-Sleep -Seconds 3
$now = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -match 'ThemeAutoSwitch\.ps1' -and $_.CommandLine -notmatch 'Get-CimInstance' }
if ($now) { Write-Output ("常驻进程已启动, PID {0}" -f ($now.ProcessId -join ',')) }
else { Write-Output '警告: 常驻进程似乎没起来, 请查看 theme-auto.log' }

# 4) 可选: 注册开机自启
if (-not $NoAutostart) {
    Write-Output ''
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir 'autostart.ps1') -Action install
} else {
    Write-Output ''
    Write-Output '已跳过开机自启 (如需启用: .\autostart.ps1 -Action install)'
}
