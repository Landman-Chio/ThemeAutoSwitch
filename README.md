# ThemeAutoSwitch

**按你自己的时间表，自动切换 Windows 深色 / 浅色模式。**

[English](#english) · 中文

一个零依赖的 PowerShell 小工具。常驻后台，到点自动切换系统界面和应用界面的深浅色。

```
19:00  →  🌙 深色
07:00  →  ☀️ 浅色
```

时间随便改，`19:00`、`1900`、`19` 三种写法都认。改完**存盘即生效**，不用重启进程。

---

## 为什么还需要这个

Windows 自带的「自动选择深色/浅色模式」有两个问题：

1. **只能按日出日落走**，时间不可自定义
2. **LTSC / 精简版系统里根本没有这一项**（设置 → 个性化 → 颜色 里找不到）

所以做了这个：时间完全可控，双击即用，不需要管理员权限。

## 与其他方案对比

| | 自带功能 | [Auto Dark Mode](https://github.com/AutoDarkMode/Windows-Auto-Night-Mode) | **ThemeAutoSwitch** |
|---|---|---|---|
| 自定义时间 | ❌ 只能日出日落 | ✅ | ✅ |
| 依赖 | 无 | 需要安装 .NET 应用 | **无，纯 PowerShell** |
| 安装体积 | — | ~50 MB | **< 20 KB** |
| 换壁纸 / 主题包 | ❌ | ✅ | ❌（有意不做，避免覆盖你的强调色） |
| 管理员权限 | — | 需要 | **不需要** |
| 可用性 | 部分版本没有 | 功能最全 | 够用就好 |

**如果你需要换壁纸、按地理位置日出日落、多套主题方案，请用 Auto Dark Mode。**
这个工具只做一件事：**按你定的时间切深浅色**，并且做到极小、透明、可读。

## 快速开始

需要 Windows 10 1809 或更高版本（Windows 11 亦可）。**不需要管理员权限。**

```powershell
# 下载后在文件夹里执行一次
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

它会：按当前时间立即切一次 → 启动后台常驻 → 注册开机自启。

也可以**双击 `launcher.vbs`** 只启动后台常驻（无控制台窗口），但不注册自启。

## 改时间

编辑 `theme-config.json`（首次运行自动生成，也可参考 `config.example.json`）：

```json
{
  "darkFrom": "19:00",
  "lightFrom": "07:00",
  "systemUI": true,
  "appsUI": true,
  "restartExplorer": false
}
```

| 字段 | 说明 |
|---|---|
| `darkFrom` | 从几点开始**深色** |
| `lightFrom` | 从几点开始**浅色** |
| `systemUI` | 切换系统界面：任务栏 / 开始菜单 / 通知中心 |
| `appsUI` | 切换应用界面：资源管理器 / 设置等窗口 |
| `restartExplorer` | 切换后是否强制重启资源管理器立即刷新（默认 `false`） |

**三种时间区间都支持：**

- `darkFrom` > `lightFrom`（`19:00` / `07:00`）→ 深色**跨越午夜**
- `darkFrom` < `lightFrom`（`07:00` / `19:00`）→ 白天深色
- 两者相同 → 一直浅色（可以用这个把系统固定在浅色）

## 手动控制

```powershell
.\ThemeAutoSwitch.ps1 -Action status      # 查看当前状态
.\ThemeAutoSwitch.ps1 -Action set-dark    # 立刻切深色
.\ThemeAutoSwitch.ps1 -Action set-light   # 立刻切浅色
.\ThemeAutoSwitch.ps1 -Action toggle      # 切换当前模式
.\ThemeAutoSwitch.ps1 -Action apply       # 按当前时间应用一次
.\ThemeAutoSwitch.ps1 -Action run         # 前台常驻（调试用，能看到输出）
```

> ⚠️ 手动切换会在**最多 20 秒后被自动纠正回来**。这是有意设计：程序持续比对「按时间应该是
> 什么」和「实际是什么」，不一致就切。这样开机时间不对、从睡眠唤醒、被别的软件改过，
> 都能自动纠正。要临时压住自动切换，就把 `darkFrom` / `lightFrom` 改成你想要的状态。

## 开机自启

```powershell
.\autostart.ps1 -Action install   # 启用
.\autostart.ps1 -Action status    # 查看
.\autostart.ps1 -Action remove    # 关闭
```

只在「启动」文件夹放一个快捷方式，不改注册表自启项。

## 它到底改了什么

**只写 HKCU 下的两个值**，位于
`HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize`：

| 值 | 深色 | 浅色 | 影响 |
|---|---|---|---|
| `SystemUsesLightTheme` | 0 | 1 | 任务栏 / 开始菜单 / 通知中心 |
| `AppsUseLightTheme` | 0 | 1 | 资源管理器、设置等应用窗口 |

改完立刻广播 `WM_SETTINGCHANGE`（`lParam = "ImmersiveColorSet"`）并调用
`SystemParametersInfo(SPI_SETTINGCHANGE)`，让已打开的窗口尽快重绘。

**不改壁纸、不改强调色、不碰系统文件、不装服务、不加驱动。** 卸载就是删文件夹。

## 卸载

```powershell
.\autostart.ps1 -Action remove
```

然后在任务管理器结束 `powershell.exe`（命令行含 `ThemeAutoSwitch.ps1` 的那个），
删掉整个文件夹即可。

## 排查

日志在 `theme-auto.log`（超过 200 KB 自动轮转为 `.old`）：

```
[2026-10-12 09:33:48] === ThemeAutoSwitch 启动 === 深色 19:00 / 浅色 07:00 | 系统=True 应用=True 刷新资源管理器=False
[2026-10-12 09:34:08] 配置已热重载: 深色 00:00 / 浅色 23:59
[2026-10-12 09:34:11] 已切换到深色 [系统界面+应用界面] 系统:浅->深 应用:浅->深
```

| 现象 | 处理 |
|---|---|
| 任务栏变了但资源管理器没变 | 资源管理器不总立即重绘。把 `restartExplorer` 设为 `true` |
| 改了配置没反应 | 确认是合法 JSON；日志里应出现「配置已热重载」 |
| 手动切了又被切回去 | 设计如此，见上面「手动控制」 |
| 完全没动静 | 日志里没有「启动」行 = 进程没起来，重跑 `install.ps1` |
| 时间判定反了 | 记住 `darkFrom` 是**深色开始**的时刻 |

## 录制演示（可复现的验证）

所有关键行为都用真实注册表读回验证过：

| 验证项 | 结果 |
|---|---|
| 手动切深色 | `已切换到深色 [系统界面+应用界面] 系统:浅->深 应用:浅->深` |
| 手动切浅色 | `已切换到浅色 [系统界面+应用界面] 系统:深->浅 应用:深->浅` |
| 配置热重载 | 改文件后 20 秒内日志出现「配置已热重载」 |
| 自动切换 | 配置改为「当前应为深色」后 3 秒内自动切换 |
| 跨午夜边界 | `19:00`/`07:00` 下逐点验证：00:30 深、06:59 深、07:00 浅、19:00 深、23:59 深 |
| 不误伤其他设置 | 强调色、壁纸均未改变 |

## 技术说明

两个值得注意的实现点：

**1. 按「目标状态 vs 实际状态」比对，而不是在时间点触发事件。**
每 20 秒读一次注册表当前值，和按时间算出的应有值比对，不一致就切。
这一个设计同时解决了：开机时间不对、从睡眠/休眠唤醒、配置被改、被别的程序改动 ——
不需要为每种情况写专门的补切逻辑。

**2. 只改注册表不生效，必须广播。**
改完注册表后任务栏可能几分钟都不刷新。所以立刻广播
`WM_SETTINGCHANGE` + `ImmersiveColorSet`，并调用 `SystemParametersInfo`。

> 教训：`SetWindowCompositionAttribute` 之类的 API **返回成功不等于画面上有变化**。
> 这个项目里每个环节都做了实际读回验证，而不是只看返回值。

### 源码文件

| 文件 | 作用 |
|---|---|
| `ThemeAutoSwitch.ps1` | 主程序：常驻循环、主题读写、时间判定 |
| `launcher.vbs` | 静默启动器（无控制台窗口） |
| `install.ps1` | 一键：应用一次 + 启动常驻 + 注册自启 |
| `autostart.ps1` | 开机自启开关 |
| `theme-config.json` | 配置文件（**不进 git**，首次运行生成） |
| `config.example.json` | 带注释的配置示例 |

---

<a name="english"></a>

## English

**Automatically switch Windows between dark and light mode on your own schedule.**

A zero-dependency PowerShell utility. Runs in the background and flips the system UI and
app UI themes at the times you choose.

```
19:00  →  🌙 dark
07:00  →  ☀️ light
```

Times are flexible: `19:00`, `1900`, and `19` all work. Edit the config and it takes effect
within 20 seconds — no restart needed.

### Why this exists

Windows' built-in "Choose your mode" option can only follow sunrise/sunset, and it is
**missing entirely from LTSC / trimmed editions**. This tool gives you full control over
the times, runs without administrator rights, and is under 20 KB.

If you need wallpaper switching, geolocation-based sunrise/sunset, or multiple theme
profiles, use [Auto Dark Mode](https://github.com/AutoDarkMode/Windows-Auto-Night-Mode)
instead — it is more capable. This tool deliberately does one thing well.

### Requirements

Windows 10 1809+ or Windows 11. **No administrator rights required.**

### Quick start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

This applies the theme once for the current time, starts the background process, and
registers it to run at login.

### Configuration

`theme-config.json`:

```json
{
  "darkFrom": "19:00",
  "lightFrom": "07:00",
  "systemUI": true,
  "appsUI": true,
  "restartExplorer": false
}
```

- `darkFrom` / `lightFrom` — when dark / light mode begins
- `systemUI` — taskbar, Start menu, notification center
- `appsUI` — Explorer, Settings, and other app windows
- `restartExplorer` — force an Explorer restart for immediate refresh

If `darkFrom` is later than `lightFrom`, dark mode spans midnight. Setting both to the
same value pins the system to light mode.

### Manual control

```powershell
.\ThemeAutoSwitch.ps1 -Action status      # current state
.\ThemeAutoSwitch.ps1 -Action set-dark    # switch to dark now
.\ThemeAutoSwitch.ps1 -Action set-light   # switch to light now
.\ThemeAutoSwitch.ps1 -Action toggle      # toggle
```

> ⚠️ A manual switch will be reverted within 20 seconds by design — the process
> continuously reconciles the desired theme against the actual one, so a wrong state
> after boot, resume from sleep, or an external change is corrected automatically.

### What it actually changes

Only two values under
`HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize`:

| Value | Dark | Light | Affects |
|---|---|---|---|
| `SystemUsesLightTheme` | 0 | 1 | Taskbar, Start menu, notification center |
| `AppsUseLightTheme` | 0 | 1 | Explorer, Settings, and app windows |

It then broadcasts `WM_SETTINGCHANGE` with `"ImmersiveColorSet"` and calls
`SystemParametersInfo(SPI_SETTINGCHANGE)` so open windows repaint promptly.

**It does not touch your wallpaper, accent color, system files, services, or drivers.**
Uninstalling means deleting the folder.

### Uninstall

```powershell
.\autostart.ps1 -Action remove
```

Then end the `powershell.exe` process whose command line contains `ThemeAutoSwitch.ps1`
and delete the folder.

## License

[MIT](LICENSE)
