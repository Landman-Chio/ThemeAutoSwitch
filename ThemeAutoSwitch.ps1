<#
    ThemeAutoSwitch - 按时间自动切换 Windows 深浅模式
    ------------------------------------------------------------
    常驻后台，每秒检查时间，到点自动切换「系统界面」和「应用界面」的深浅色。
    纯用户态工具：只写 HKCU 注册表，不需要管理员权限，不装服务。

    用法:
        wscript launcher.vbs                 # 静默常驻(推荐, 无控制台窗口)
        powershell -File ThemeAutoSwitch.ps1 -Action apply    # 立即按当前时间切一次
        powershell -File ThemeAutoSwitch.ps1 -Action status   # 查看当前状态
        powershell -File ThemeAutoSwitch.ps1 -Action set-dark # 手动切深色
        powershell -File ThemeAutoSwitch.ps1 -Action set-light# 手动切浅色
#>
param(
    [ValidateSet('run','apply','status','set-dark','set-light','toggle')]
    [string]$Action = 'run'
)

$ErrorActionPreference = 'Stop'

#region ============ 路径与配置 ============
$Script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:CfgPath  = Join-Path $Script:BasePath 'theme-config.json'
$Script:LogPath  = Join-Path $Script:BasePath 'theme-auto.log'
$Script:Persona  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'

function Write-Log([string]$msg) {
    try {
        # 日志超过 200KB 就轮转一次, 避免常驻进程无限写大
        if (Test-Path $Script:LogPath) {
            $fi = Get-Item $Script:LogPath
            if ($fi.Length -gt 200KB) { Move-Item $Script:LogPath "$($Script:LogPath).old" -Force }
        }
        Add-Content -Path $Script:LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
    } catch {}
}

# 默认: 19:00 之后算深色, 07:00 之后算浅色
$Script:Defaults = [ordered]@{
    darkFrom  = '19:00'
    lightFrom = '07:00'
    systemUI  = $true     # 系统界面(任务栏/开始菜单/通知中心)
    appsUI    = $true     # 应用界面(资源管理器/设置等)
    restartExplorer = $false   # 切换后是否强制重启资源管理器立即刷新
}

function Get-Config {
    $raw = $null
    if (Test-Path $Script:CfgPath) {
        try { $raw = Get-Content -Raw -Encoding UTF8 $Script:CfgPath | ConvertFrom-Json } catch { $raw = $null }
    }
    $cfg = [ordered]@{}
    foreach ($k in $Script:Defaults.Keys) {
        if ($raw -and ($raw.PSObject.Properties.Name -contains $k)) { $cfg[$k] = $raw.$k } else { $cfg[$k] = $Script:Defaults[$k] }
    }
    return $cfg
}

function Ensure-Config {
    if (-not (Test-Path $Script:CfgPath)) {
        ($Script:Defaults | ConvertTo-Json) | Set-Content $Script:CfgPath -Encoding UTF8
        Write-Log "已生成默认配置: $($Script:CfgPath)"
    }
}

# 解析 "HH:mm" / "H:mm" / "HHmm" / "7" 等写法
function Parse-TimeOfDay([string]$s) {
    if (-not $s) { return $null }
    $t = $s.Trim()
    if ($t -match '^(\d{1,2}):(\d{2})$') {
        $h = [int]$Matches[1]; $m = [int]$Matches[2]
    } elseif ($t -match '^(\d{4})$') {
        $h = [int]$t.Substring(0, 2); $m = [int]$t.Substring(2, 2)
    } elseif ($t -match '^(\d{1,2})$') {
        $h = [int]$t; $m = 0
    } else { return $null }
    if ($h -lt 0 -or $h -gt 23 -or $m -lt 0 -or $m -gt 59) { return $null }
    return [TimeSpan]::FromHours($h) + [TimeSpan]::FromMinutes($m)
}
#endregion

#region ============ 主题读写 ============
function Get-ThemeState {
    $sys = (Get-ItemProperty $Script:Persona -Name 'SystemUsesLightTheme' -EA SilentlyContinue).SystemUsesLightTheme
    $app = (Get-ItemProperty $Script:Persona -Name 'AppsUseLightTheme' -EA SilentlyContinue).AppsUseLightTheme
    if ($null -eq $sys) { $sys = 1 }
    if ($null -eq $app) { $app = 1 }
    return [pscustomobject]@{ SystemLight = ($sys -eq 1); AppsLight = ($app -eq 1); SysRaw = $sys; AppRaw = $app }
}

Add-Type -Namespace ThemeAuto -Name Native -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, int Msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(int uiAction, int uiParam, IntPtr pvParam, int fWinIni);
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
'@

# 广播主题变更, 让已打开的窗口(任务栏、开始菜单、资源管理器等)立即重绘
function Invoke-ThemeBroadcast {
    $r = [IntPtr]::Zero
    # HWND_BROADCAST=0xffff, WM_SETTINGCHANGE=0x001A
    [void][ThemeAuto.Native]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [IntPtr]::Zero, 'ImmersiveColorSet', 2, 1000, [ref]$r)
    # SPI_SETTINGCHANGE=0x001A, SPIF_UPDATEINIFILE|SPIF_SENDCHANGE=3
    [void][ThemeAuto.Native]::SystemParametersInfo(0x001A, 0, [IntPtr]::Zero, 3)
}

function Restart-Explorer {
    try {
        Get-Process explorer -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep -Milliseconds 900
        if (-not (Get-Process explorer -EA SilentlyContinue)) {
            Start-Process explorer.exe -EA SilentlyContinue
        }
        Write-Log '已重启资源管理器'
    } catch { Write-Log ("重启资源管理器失败: {0}" -f $_.Exception.Message) }
}

# 切换到指定模式
function Set-ThemeMode([bool]$dark, [string]$reason, $cfg) {
    $before = Get-ThemeState
    $light = if ($dark) { 0 } else { 1 }

    $changed = @()
    if ($cfg.systemUI) {
        if ($before.SysRaw -ne $light) {
            Set-ItemProperty $Script:Persona -Name 'SystemUsesLightTheme' -Value $light -Type DWord -EA SilentlyContinue
            $changed += '系统界面'
        }
    }
    if ($cfg.appsUI) {
        if ($before.AppRaw -ne $light) {
            Set-ItemProperty $Script:Persona -Name 'AppsUseLightTheme' -Value $light -Type DWord -EA SilentlyContinue
            $changed += '应用界面'
        }
    }

    if ($changed.Count -eq 0) {
        Write-Log ("无需切换(已是{0}色) - {1}" -f $(if ($dark) { '深' } else { '浅' }), $reason)
        return $false
    }

    Invoke-ThemeBroadcast
    if ($cfg.restartExplorer) { Restart-Explorer }

    $after = Get-ThemeState
    Write-Log ("已切换到{0}色 [{1}] 系统:{2}->{3} 应用:{4}->{5}" -f `
        $(if ($dark) { '深' } else { '浅' }), ($changed -join '+'),
        $(if ($before.SystemLight) { '浅' } else { '深' }), $(if ($after.SystemLight) { '浅' } else { '深' }),
        $(if ($before.AppsLight) { '浅' } else { '深' }), $(if ($after.AppsLight) { '浅' } else { '深' }))
    return $true
}
#endregion

#region ============ 时间判定 ============
# 返回当前时间点应该处于的模式: $true = 深色
function Get-DesiredDark($cfg) {
    $darkAt  = Parse-TimeOfDay $cfg.darkFrom
    $lightAt = Parse-TimeOfDay $cfg.lightFrom
    if ($null -eq $darkAt -or $null -eq $lightAt) {
        Write-Log ("配置里的时间格式不对: darkFrom='{0}' lightFrom='{1}', 已回退默认 19:00/07:00" -f $cfg.darkFrom, $cfg.lightFrom)
        $darkAt  = [TimeSpan]::FromHours(19)
        $lightAt = [TimeSpan]::FromHours(7)
    }
    $now = (Get-Date).TimeOfDay

    if ($darkAt -gt $lightAt) {
        # 常见情形: 19:00 深 -> 次日 07:00 浅。 深色区间 = [darkAt, 24h) ∪ [0, lightAt)
        return ($now -ge $darkAt) -or ($now -lt $lightAt)
    } elseif ($darkAt -lt $lightAt) {
        # 深色区间 = [darkAt, lightAt)
        return ($now -ge $darkAt) -and ($now -lt $lightAt)
    } else {
        # 两个时间相同: 视为一直浅色
        return $false
    }
}
#endregion

#region ============ 动作 ============
function Show-Status {
    $cfg = Get-Config
    $st  = Get-ThemeState
    $desired = Get-DesiredDark $cfg
    $currentDark = (-not $st.SystemLight)
    Write-Output '=== ThemeAutoSwitch 状态 ==='
    Write-Output ("配置: 深色起始 {0} / 浅色起始 {1}" -f $cfg.darkFrom, $cfg.lightFrom)
    Write-Output ("      切换系统界面={0} 应用界面={1} 强制刷新资源管理器={2}" -f $cfg.systemUI, $cfg.appsUI, $cfg.restartExplorer)
    Write-Output ("当前: 系统界面={0}色, 应用界面={1}色" -f $(if ($st.SystemLight) { '浅' } else { '深' }), $(if ($st.AppsLight) { '浅' } else { '深' }))
    Write-Output ("按时间应为: {0}色" -f $(if ($desired) { '深' } else { '浅' }))
    if ($desired -ne $currentDark) {
        Write-Output '  -> 与当前不一致, 下次检查(最多 20 秒)会切换'
    } else {
        Write-Output '  -> 与当前一致'
    }
}

function Invoke-ApplyOnce {
    $cfg = Get-Config
    $desired = Get-DesiredDark $cfg
    [void](Set-ThemeMode $desired ("按当前时间" ) $cfg)
}

function Invoke-Run {
    Ensure-Config
    $cfg = Get-Config
    $darkAt  = Parse-TimeOfDay $cfg.darkFrom
    $lightAt = Parse-TimeOfDay $cfg.lightFrom
    Write-Log ("=== ThemeAutoSwitch 启动 === 深色 {0} / 浅色 {1} | 系统={2} 应用={3} 刷新资源管理器={4}" -f `
        $cfg.darkFrom, $cfg.lightFrom, $cfg.systemUI, $cfg.appsUI, $cfg.restartExplorer)

    # 每隔多久检查一次。切换只会在时分变化时发生, 20 秒足够且开销可忽略
    $Script:LastCfgWrite = (Get-Item $Script:CfgPath).LastWriteTime
    $Script:Cfg = $cfg

    while ($true) {
        try {
            # 配置被改了就热重载, 不用重启进程
            $wt = (Get-Item $Script:CfgPath).LastWriteTime
            if ($wt -ne $Script:LastCfgWrite) {
                $Script:LastCfgWrite = $wt
                $Script:Cfg = Get-Config
                Write-Log ("配置已热重载: 深色 {0} / 浅色 {1}" -f $Script:Cfg.darkFrom, $Script:Cfg.lightFrom)
            }

            $wantDark = Get-DesiredDark $Script:Cfg
            $st = Get-ThemeState
            $isDark = (-not $st.SystemLight)
            # 按"目标状态 vs 实际状态"比对, 这样开机时间不对、从睡眠醒来、手动改过
            # 都能自动纠正回来
            if ($wantDark -ne $isDark) {
                [void](Set-ThemeMode $wantDark '时间到达' $Script:Cfg)
            }
        } catch {
            Write-Log ("循环异常: {0}" -f $_.Exception.Message)
        }
        Start-Sleep -Seconds 20
    }
}
#endregion

# 任何动作都要先保证配置文件存在(首次运行自动生成), 不只是常驻模式
Ensure-Config

switch ($Action) {
    'status'    { Show-Status }
    'apply'     { Invoke-ApplyOnce }
    'set-dark'  { $c = Get-Config; [void](Set-ThemeMode $true  '手动命令' $c) }
    'set-light' { $c = Get-Config; [void](Set-ThemeMode $false '手动命令' $c) }
    'toggle'    {
        $c = Get-Config
        $st = Get-ThemeState
        [void](Set-ThemeMode ($st.SystemLight) '手动切换' $c)
    }
    'run'       { Invoke-Run }
}
