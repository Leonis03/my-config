# Windows Terminal 与 WSL / PowerShell 7 配置优化总结

本文档汇总了本次关于 **Windows Terminal**、**PowerShell 7** 以及 **WSL (Ubuntu Zsh)** 路径继承、自动重定向、历史自动补全及环境配置的全部结论与实际改动记录。

---

## 一、 核心技术结论与原理解析

### 1. Windows Terminal 新标签页路径继承
* **问题现象**：在文件夹右键“在终端中打开”进入了该文件夹，但点击 `+` 或按 `Ctrl+Shift+T` 新建标签页时，路径被强制重置回 `%USERPROFILE%`（`C:\Users\用户名`）。
* **核心原因**：Windows Terminal 默认 profile 中设置了 `"startingDirectory": "%USERPROFILE%"`。
* **解决方案**：在 `settings.json` 的 `profiles.defaults` 中设置 `"startingDirectory": null`（或清空起始目录）。终端会在每次新建标签页时继承启动当前窗口的上下文工作目录。

### 2. 管理员模式下默认进入 `System32` 的处理机制
* **问题现象**：当以管理员身份启动终端、或者从 `Win + X` 快捷菜单打开终端时，Windows 默认将工作目录分配为 `C:\Windows\System32`（WSL 下为 `/mnt/c/Windows/System32`）。
* **解决方案**：
  * Windows Terminal 的 `settings.json` 为静态 JSON，不支持条件分支逻辑；
  * 因此最佳方案是在 **Shell 的启动初始化脚本**（PowerShell 的 `$PROFILE` 与 Linux 的 `~/.bashrc` / `~/.zshrc`）中加入路径检测代码：当检测到当前路径为 `System32` / `SysWOW64` 时自动执行 `cd ~`，若是普通文件夹启动则不做任何改动。
  * **安全性说明**：此脚本仅在**终端启动/新开标签页的瞬间执行一次**，后续日常在终端里手动执行 `cd /mnt/c/Windows/System32` 或查看系统文件时**绝对不会**被弹回。

### 3. `settings.json` 路径变量替换
* `C:\Program Files` 对应的 Windows 系统内置环境变量为 **`%ProgramFiles%`**。
* Windows Terminal 支持在 `commandline` 和 `icon` 等字段中直接解析 `%ProgramFiles%`、`%ProgramFiles(x86)%`、`%LocalAppData%` 等变量。

### 4. PowerShell 与 Windows PowerShell 官方命名体系
* **Windows PowerShell (v1.0 ~ 5.1)**：基于旧 .NET Framework，属于 Windows 系统内置组件，专属于 Windows，可执行文件为 `powershell.exe`。
* **PowerShell (v6.0 / 7.x+)**：基于现代跨平台开源 .NET (Core)，支持 Windows、macOS 和 Linux，去掉了 "Windows" 前缀，可执行文件统一命名为 `pwsh.exe`，以此实现与系统内置版本并行共存（Side-by-Side）。

### 5. 终端历史命令灰色建议（Ghost Text / Inline Autosuggestion）
* **PowerShell 7**：内置 `PSReadLine` 模块的 `PredictionSource` 及 `InlineView`。
* **WSL (Ubuntu)**：通过安装 **Oh My Zsh + `zsh-autosuggestions`** 插件实现完全一致的体验（按 `→` 或 `End` 采纳整行建议，`Alt + f` 采纳单词）。

### 6. Zsh 提示符完整绝对路径展示
* Oh My Zsh 默认 `robbyrussell` 主题使用 `%c`（仅显示当前文件夹名）。
* 切换为包含 `~` 的完整路径使用 **`%~`**（例如 `~/Desktop/CODE/wt`）。
* 切换为严格绝对路径使用 **`%d`** 或 **`%/`**（例如 `$HOME/Desktop/CODE/wt`）。

---

## 二、 对系统与配置文件的实际改动清单

本次对话期间，已对你的本地系统及配置文件执行了以下实质性改动：

### 1. PowerShell 7 配置文件修改
* **目标文件**：`C:\Users\<your-windows-user>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`
* **改动内容**：在文件末尾追加了针对 `System32` 和 `SysWOW64` 的自动跳转逻辑：
  ```powershell
  # ------------------------------------------------------------------------------
  # 7. Auto-navigate from System32 to ~ (User Home Directory)
  # ------------------------------------------------------------------------------
  if ($PWD.Path -eq "$env:windir\System32" -or $PWD.Path -eq "$env:windir\SysWOW64") {
      Set-Location ~
  }
  ```
* **改动效果**：以管理员启动或从 System32 启动 PowerShell 7 时自动回到 `C:\Users\<your-windows-user>`；从项目文件夹启动时保持原目录不变。

---

### 2. WSL Ubuntu 环境及 Zsh 配置
* **目标文件**：`\\wsl.localhost\Ubuntu\home\<user>\.zshrc`
* **插件安装**：克隆并安装了 `zsh-autosuggestions` 插件至：
  `~/.oh-my-zsh/custom/plugins/zsh-autosuggestions`
* **改动内容**：
  1. 在 `~/.zshrc` 中启用了插件：`plugins=(git zsh-autosuggestions)`
  2. 从原 `~/.bashrc` 同步并恢复了所有关键环境变量与工具配置：
     * **NVM / Node.js**（v24.19.0）
     * **PNPM**（11.21.0）
     * **Antigravity CLI (`agy`)**（1.1.16）
     * **代理环境变量**（Clash `<proxy-port>` 端口代理配置）
     * **VS Code 命令行**（`code` 启动器路径）
     * **Fcitx5 输入法环境变量**
     * **WSL System32 自动重定向逻辑**：
       ```zsh
       # WSL: avoid changing to Windows system directories (system32/syswow64)
       if [[ "${PWD:l}" =~ ^/mnt/[a-z]/windows/(system32|syswow64) ]]; then
         cd ~
       fi
       ```
* **改动效果**：
  * 解决运行 Oh My Zsh 安装脚本后找不到 `pnpm`、`agy`、`nvm` 等命令的问题；
  * 终端输入时自动显示灰色历史预测文字；
  * 当在 Windows 端以管理员打开 WSL 时自动切回 Ubuntu 家目录 `$HOME`。

---

## 三、 快捷键与常用指令速查

| 场景 | 命令 / 快捷键 | 说明 |
| :--- | :--- | :--- |
| **Windows Terminal 复制当前标签页** | `Ctrl + Shift + D` | 复制并继承当前活动标签页的实时路径与配置 |
| **Windows Terminal 打开 JSON 设置** | `Ctrl + Shift + ,` | 快速编辑 `settings.json` |
| **PowerShell 7 采纳预测建议** | 右方向键 `→` | 采纳整行灰色建议 |
| **PowerShell 7 逐词采纳** | `Ctrl + →` | 逐个单词采纳预测建议 |
| **WSL Zsh 采纳预测建议** | 右方向键 `→` / `End` | 采纳整行灰色建议 |
| **WSL Zsh 逐词采纳** | `Alt + f` | 逐个单词采纳预测建议 |
| **WSL Zsh 重新加载配置** | `source ~/.zshrc` | 配置文件修改后立即生效 |
