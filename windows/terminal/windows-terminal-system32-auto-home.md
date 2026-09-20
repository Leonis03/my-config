# Windows Terminal 启动路径配置与 System32 / SysWOW64 自动转 ~ 指南

本文档解答 Windows Terminal 默认启动路径机制，并提供三大核心配置：
1. **使用命令将 Windows Terminal 默认路径修改为继承打开时的实际工作目录（`startingDirectory: null`）**；
2. **在 PowerShell 配置文件中加入检测与路径上报（System32 / SysWOW64 自动转 `~`、`OSC 9;9` 实时上报）**；
3. **优化 PowerShell 7 右键菜单为 Windows Terminal 原生调用（彻底解决右键打开后点击 `+` 继承路径及标题闪烁问题）**。

---

## 一、 Windows Terminal 默认路径机制与解答

### 1. Windows Terminal 默认配置是在 `~` 打开吗？
* **是的。**
* Windows Terminal 默认安装后的初始配置中，`startingDirectory` 默认为 `%USERPROFILE%`（即用户主目录 `C:\Users\<用户名>` / `~`）。
* 这意味着在默认配置下，无论你在哪个文件夹打开终端或新建标签页，都会被固定重定向到用户家目录 `~`。

### 2. 为什么需要修改为“wt 打开时的路径”？
* 如果保持默认的 `~`，在资源管理器中右键任意文件夹选择**“在终端中打开”（Open in Terminal）**、或者在命令行中运行 `wt` 时，终端**无法继承**当前文件夹路径。
* 将 `profiles.defaults.startingDirectory` 设为 `null`（或在 UI 设置中清空“起始目录”），Windows Terminal 就会**自动继承打开 `wt` 时所在的物理路径**（例如在 `D:\Projects` 右键打开，终端初始路径就是 `D:\Projects`）。

### 3. 为什么又需要针对 System32 做自动跳转？
* 将 `startingDirectory` 改为 `null` 后，当以**管理员身份运行**终端、或通过 `Win + X`（快捷菜单）启动时，Windows 系统默认分配给终端的初始路径是 `C:\Windows\System32`（或 32 位环境下的 `C:\Windows\SysWOW64`）。
* Windows Terminal 的 JSON 配置不支持写 `if-else` 条件判断逻辑。
* **最佳实践**：
  1. 在 Windows Terminal 中配置 `"startingDirectory": null`（确保右键继承路径）；
  2. 在 PowerShell 的启动脚本（`$PROFILE`）中加入判断：**仅在初始路径为 System32 / SysWOW64 时才自动切回 `~`**；
  3. 配置 `OSC 9;9` 实时上报与右键原生调用，确保新建标签页（`+`）与复制标签页（`Ctrl+Shift+D`）均能继承路径。

---

## 二、 命令 1：修改 Windows Terminal 配置（继承 wt 打开时的路径）

以下 PowerShell 命令会自动定位 Windows Terminal 的配置文件 `settings.json`，并将 `profiles.defaults.startingDirectory` 设置为 `null`：

```powershell
# 1. 常见 Windows Terminal 配置文件路径候选
$wtSettingsPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)

# 2. 定位存在的配置文件
$settingsFile = $wtSettingsPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($settingsFile) {
    # 备份原文件
    Copy-Item -Path $settingsFile -Destination "$settingsFile.bak" -Force
    
    # 读取并解析 JSON
    $json = Get-Content -Raw -Path $settingsFile -Encoding utf8 | ConvertFrom-Json
    
    # 确保 profiles.defaults 节点存在
    if (-not $json.profiles.defaults) {
        $json.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    
    # 设置 startingDirectory 为 null (继承启动路径)
    $json.profiles.defaults.startingDirectory = $null
    
    # 写回 settings.json (保持 UTF-8 编码与深度)
    $json | ConvertTo-Json -Depth 100 | Set-Content -Path $settingsFile -Encoding utf8
    Write-Host "✅ 成功将 Windows Terminal 的 startingDirectory 修改为 null（继承打开时的路径）" -ForegroundColor Green
} else {
    Write-Warning "未找到 Windows Terminal 配置文件 settings.json"
}
```

---

## 三、 命令 2：PowerShell 启动检测与路径上报（写入 `$PROFILE`）

### 1. 核心逻辑

```powershell
# ------------------------------------------------------------------------------
# 7. Auto-navigate from System32 / SysWOW64 to ~ (User Home Directory)
# ------------------------------------------------------------------------------
if ($PWD.Path -eq "$env:windir\System32" -or $PWD.Path -eq "$env:windir\SysWOW64") {
    Set-Location ~
}

# ------------------------------------------------------------------------------
# 8. Windows Terminal Shell Integration: Path Reporting (OSC 9;9)
# ------------------------------------------------------------------------------
function prompt {
    $loc = $($ExecutionContext.SessionState.Path.CurrentLocation)
    $esc = [char]27
    Write-Host -NoNewline "$esc]9;9;`"$loc`"$esc"
    "PS $loc$('>' * ($nestedPromptLevel + 1)) "
}
```

### 2. 一键写入 `$PROFILE`（PowerShell 命令）

在 PowerShell（PowerShell 7 `pwsh` 或 Windows PowerShell 5.1）中运行以下命令：

```powershell
# 1. 确保 Profile 所在目录及文件存在
if (!(Test-Path -Path $PROFILE)) {
    $profileDir = Split-Path -Path $PROFILE -Parent
    if (!(Test-Path -Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

# 2. 追加检测跳转与路径实时上报逻辑（纯 ASCII 编码）
@'

# Auto-navigate from System32 to ~ (User Home Directory)
if ($PWD.Path -eq "$env:windir\System32" -or $PWD.Path -eq "$env:windir\SysWOW64") {
    Set-Location ~
}

# Windows Terminal Shell Integration: Path Reporting (OSC 9;9)
function prompt {
    $loc = $($ExecutionContext.SessionState.Path.CurrentLocation)
    $esc = [char]27
    $bel = [char]7
    Write-Host -NoNewline "$esc]9;9;`"$loc`"$bel"
    "PS $loc$('>' * ($nestedPromptLevel + 1)) "
}
'@ | Out-File -FilePath $PROFILE -Append -Encoding ascii
```

---

## 四、 命令 3：优化 PowerShell 7 右键菜单为 Native Windows Terminal 调用

### 1. 为什么官方默认右键菜单会导致新建标签页无法继承路径？
* **原版机制**：PowerShell 7 官方 MSI 安装的右键菜单注册命令为：
  `pwsh.exe -WorkingDirectory "%V!" -Command "$host.UI.RawUI.WindowTitle = 'PowerShell 7 (x64)'"`
  这是直接调用 `pwsh.exe`，由 Windows 11 DefTerm 机制隐式托管到 Windows Terminal。
* **导致两大体验问题**：
  1. **标题闪烁**：启动时标签页标题先显示长命令路径 `C:\Program Files\PowerShell\...`，后才变为 `PowerShell 7 (x64)`；
  2. **新建标签页（`+`）丢失路径**：Windows Terminal 窗口本体未被传入 `-d` 根工作目录，点击顶部 `+` 按钮新建标签页时找不到窗口根目录，回退到 `~`。

### 2. 优化方案与一键配置命令（PowerShell 管理员身份运行）

将右键菜单升级为直接调用 `wt.exe -p "PowerShell" -d "%V"`：

```powershell
# 1. 自动备份原注册表项
$backupPath = "$env:TEMP\pwsh7_menu_backup.reg"
reg export "HKLM\SOFTWARE\Classes\Directory\ContextMenus\PowerShell7x64" $backupPath /y

# 2. 更新右键普通打开（openpwsh）与管理员打开（runas）
$wtPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
$wtCmd = "`"$wtPath`" -p `"PowerShell`" -d `"%V`""

Set-ItemProperty -Path "HKLM:\SOFTWARE\Classes\Directory\ContextMenus\PowerShell7x64\shell\openpwsh\command" `
                 -Name "(Default)" `
                 -Value $wtCmd

Set-ItemProperty -Path "HKLM:\SOFTWARE\Classes\Directory\ContextMenus\PowerShell7x64\shell\runas\command" `
                 -Name "(Default)" `
                 -Value $wtCmd

Write-Host "✅ 成功将 PowerShell 7 右键菜单升级为 Windows Terminal 原生调用！" -ForegroundColor Green
```

---

## 五、 生效与验证测试

### 1. 立即生效
在当前 PowerShell 窗口中运行：
```powershell
. $PROFILE
```

### 2. 验证场景与效果对比

| 测试场景 | 操作方式 | 预期结果 |
| :--- | :--- | :--- |
| **右键文件夹打开** | 在任意文件夹（如 `D:\Projects`）右键选择「PowerShell 7 > Open here」 | 原生显示 `PowerShell` 标题（无路径闪烁），直接进入 `D:\Projects` |
| **新建标签页** | 点击顶部 <kbd>+</kbd> 按钮或按 <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd> | **自动以 `D:\Projects` 为起始目录新建标签页** ✅ |
| **复制标签页** | 按 <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>D</kbd> | 按照 `OSC 9;9` 实时克隆当前动态工作目录 ✅ |
| **管理员启动** | 右键 Windows Terminal 图标选择“以管理员身份运行” | 自动从 `System32` 切回至 `C:\Users\<用户名>`（`~`） |
| **日常手动操作** | 终端内手动执行 `cd C:\Windows\System32` | 正常停留在 System32 目录，不会被误弹回 |

---

## 六、 对应文件与注册表路径汇总

* **Windows Terminal 配置文件**：`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`
* **PowerShell 7 Profile**：`$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`
* **PowerShell 7 右键菜单注册表项**：`HKLM\SOFTWARE\Classes\Directory\ContextMenus\PowerShell7x64`
* **Windows PowerShell 5.1 Profile**：`$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`\n