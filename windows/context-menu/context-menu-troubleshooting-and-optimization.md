
> **生成时间**：2026-08-21  
> **文档位置**：桌面 (`右键菜单排查与优化总结.md`)

---

## 目录
1. [ContextMenuMgr 项目架构与核心理念分析](#1-contextmenumgr-项目架构与核心理念分析)
2. [AMD Software: Adrenalin Edition 排查与屏蔽](#2-amd-software-adrenalin-edition-排查与屏蔽)
3. [Open in Terminal 排查、修复与图标优化](#3-open-in-terminal-排查修复与图标优化)
4. [ContextMenuMgr 拦截机制与服务状态答疑](#4-contextmenumgr-拦截机制与服务状态答疑)
5. [新增 Open in WSL 快捷右键菜单](#5-新增-open-in-wsl-快捷右键菜单)
6. [WSL 终端历史命令联想补全（类似 pwsh）配置建议](#6-wsl-终端历史命令联想补全配置建议)
7. [本次操作对系统注册表的改动清单](#7-本次操作对系统注册表的改动清单)

---

## 1. ContextMenuMgr 项目架构与核心理念分析

### 🌟 核心理念：“先拦截，再审核”
`ContextMenuMgr`（Context Menu Manager Plus）基于 **.NET 10 + WPF-UI** 开发，与市面上普通右键开关工具最大的区别在于：
* **主动防御**：后台服务实时监控注册表，当检测到第三方软件插入未知右键菜单时，先自动置为 **Quarantine（隔离禁用）** 状态，由用户在「待审核」列表中决定是否放行。
* **双模态支持**：同时支持传统菜单（Classic `shell` / `shellex`）与 Windows 11 现代菜单（Packaged COM / MSIX AppX）。

### 🏛️ 四大进程与权限链路模型
1. **链路 A (常规运行)**：`Frontend -> Named Pipe -> Backend Windows Service (LocalSystem)`，普通开关和扫描不弹 UAC 提权。
2. **链路 B (服务运维)**：`Frontend -> UAC (runas) -> Bootstrapper`，仅用于服务的安装、卸载和修复。
3. **链路 C (跨桌面唤醒)**：`Service -> WTS Token -> CreateProcessAsUser`，在用户交互桌面拉起托盘与通知。
4. **链路 D (COM 安全探测)**：`Frontend -> ProbeHost (C++ 独立进程)`，沙箱化枚举第三方 Shell 扩展 DLL，崩溃不影响主界面。

---

## 2. AMD Software: Adrenalin Edition 排查与屏蔽

### ❓ 为什么在 ContextMenuMgr 中搜“AMD Software”搜不到？
* **右键菜单类型**：属于 **Windows 11 Packaged COM 现代扩展**，包名为 `AdvancedMicroDevicesInc-RSXCM`。
* **注册名与显示名不一致**：
  * 清单与注册表中登记的静态名称为 **`Catalyst Context Menu extension`**（CLSID: `{FDADFEE3-02D1-4E7C-A511-380F4C98D73B}`）。
  * 菜单中看到的 `AMD Software: Adrenalin Edition` 是后台 `atiacm64.dll` 在右键被弹出时动态从资源库提取渲染的。
* **APP 检索方式**：在 ContextMenuMgr 中搜索 **`Catalyst`**、**`atiacm`** 或 **`RSXCM`** 即可找到。

### 🛡️ 屏蔽该项对应的注册表
在当前用户屏蔽列表中添加了该 CLSID（已成功在右键中隐藏）：
* **路径**：`HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Shell Extensions\\Blocked`
* **键值**：`{fdadfee3-02d1-4e7c-a511-380f4c98d73b}` = `"Catalyst Context Menu extension"`

---

## 3. Open in Terminal 排查、修复与图标优化

### ❓ 为什么 Terminal 开关开启，桌面和 D 盘根目录却没有？
1. **对象类型机制**：
   * 桌面空白处对应 **`DesktopBackground`**。
   * 磁盘根目录（如 `D:\\`）对应 **`Drive\\Background`**。
   * 子文件夹内部对应 **`Directory\\Background`**。
2. **微软官方配置缺陷**：
   * 微软在 `Microsoft.WindowsTerminal` 的官方应用清单中，**仅**声明了 `Directory` 和 `Directory\\Background`，遗漏了 `DesktopBackground` 和 `Drive\\Background`。
3. **UWP 扩展挂起现象**：
   * 当系统安装了其它 Shell 扩展（如 PowerShell 7）或 Explorer 刷新时，后台运行中的 Windows Terminal UWP COM 代理进程偶发性断开挂载。

### 🛠️ 实施的修复与全场景注册
已通过标准注册表 Shell 键将 `Windows Terminal` 完整注册至以下 5 个场景：
1. **桌面空白处** (`DesktopBackground`)
2. **磁盘驱动器根目录空白处** (`Drive\\Background`，带 `-d "%V"` 自动定位)
3. **磁盘驱动器盘符图标** (`Drive`，带 `-d "%1"`)
4. **普通文件夹内部空白处** (`Directory\\Background`，带 `-d "%V"`)
5. **普通文件夹图标** (`Directory`，带 `-d "%1"`)

### 🎨 修复官方图标显示
* **原因**：之前直接指向 `wt.exe`（0 字节 UWP 桩文件），Explorer 无法提取嵌入图标，显示为默认蓝白窗口。
* **解决**：从 Terminal 官方包中提取了高清矢量 `terminal.ico`（存放在 `%LOCALAPPDATA%\\Microsoft\\WindowsTerminal\\terminal.ico`），并统一将注册表的 `Icon` 属性指向该真实图标。

---

## 4. ContextMenuMgr 拦截机制与服务状态答疑

1. **自动拦截问题**：
   * 后台服务运行时，**会自动拦截并隔离新检测到的右键项**（加入「待审核」队列），这是正常设计。
   * 若要安装大型软件/驱动，可在设置中临时 **「卸载服务」** 或在任务管理器中右键 **停止服务**；安装完成后点击 **「安装或修复服务」** 即可瞬间恢复。
2. **APP 关闭后服务是否生效**：
   * **是的**。设置中默认开启「关闭主界面后保留后端服务和托盘进程」，点击右上角 `❌` 仅退出 UI 界面，后台服务与托盘程序仍保持实时监控与防护。

---

## 5. 新增 Open in WSL 快捷右键菜单

已为您系统配置了 **「Open in WSL」** 右键菜单：
* **终端联动**：右键点击后，自动调用 Windows Terminal 打开 **`Ubuntu`** 标签页，并自动 `cd` 进入当前右键所在的目录路径。
* **专属图标**：绑定了系统自带的官方 WSL 企鹅图标（`C:\\Program Files\\WSL\\wslsettings\\Assets\\wsl.ico`）。
* **覆盖场景**：桌面空白处、磁盘根目录（如 `D:\\`）、普通文件夹及文件夹内部空白处。

---

## 6. WSL 终端历史命令联想补全（类似 pwsh）配置建议

若希望在 WSL 终端中获得与 PowerShell 相同的**灰色历史命令自动联想补全（按 `→` 采纳）**功能：

### 方案一：Zsh + zsh-autosuggestions（最推荐）
在 WSL 中依次执行：
```bash
sudo apt update && sudo apt install zsh git curl -y
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
# 修改 ~/.zshrc 中的 plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source ~/.zshrc
```

### 方案二：Fish Shell（开箱即用，零配置自带）
```bash
sudo apt install fish -y
# 输入 fish 即可体验，或 chsh -s $(which fish) 设为默认
```

### 方案三：保留原生 Bash + ble.sh
```bash
git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git
make -C ble.sh install PREFIX=~/.local
echo 'source ~/.local/share/blesh/ble.sh' >> ~/.bashrc
source ~/.bashrc
```

---

## 7. 本次操作对系统注册表的改动清单

| 注册表目标路径 | 键值名称 | 类型 | 数据内容 / 作用 |
| :--- | :--- | :--- | :--- |
| `HKCU\\Software\\...\\Shell Extensions\\Blocked` | `{fdadfee3-02d1-4e7c-a511-380f4c98d73b}` | REG_SZ | `"Catalyst Context Menu extension"`（屏蔽 AMD 右键项） |
| `HKCU\\Software\\Classes\\DesktopBackground\\shell\\WindowsTerminal` | `(default)`, `Icon` | REG_SZ | `"Open in Terminal"`, 绑定 `terminal.ico` |
| `HKCU\\Software\\Classes\\DesktopBackground\\shell\\WindowsTerminal\\command` | `(default)` | REG_SZ | `"...\wt.exe"` |
| `HKCU\\Software\\Classes\\Drive\\Background\\shell\\WindowsTerminal` | `(default)`, `Icon` | REG_SZ | `"Open in Terminal"`, 绑定 `terminal.ico` |
| `HKCU\\Software\\Classes\\Drive\\Background\\shell\\WindowsTerminal\\command` | `(default)` | REG_SZ | `"...\wt.exe" -d "%V"` |
| `HKCU\\Software\\Classes\\Drive\\shell\\WindowsTerminal\\command` | `(default)` | REG_SZ | `"...\wt.exe" -d "%1"` |
| `HKCU\\Software\\Classes\\Directory\\Background\\shell\\WindowsTerminal\\command` | `(default)` | REG_SZ | `"...\wt.exe" -d "%V"` |
| `HKCU\\Software\\Classes\\Directory\\shell\\WindowsTerminal\\command` | `(default)` | REG_SZ | `"...\wt.exe" -d "%1"` |
| `HKCU\\Software\\Classes\\DesktopBackground\\shell\\OpenInWSL` | `(default)`, `Icon` | REG_SZ | `"Open in WSL"`, 绑定 `wsl.ico` |
| `HKCU\\Software\\Classes\\DesktopBackground\\shell\\OpenInWSL\\command` | `(default)` | REG_SZ | `"...\wt.exe" -p "Ubuntu"` |
| `HKCU\\Software\\Classes\\Drive\\Background\\shell\\OpenInWSL\\command` | `(default)` | REG_SZ | `"...\wt.exe" -p "Ubuntu" -d "%V"` |
| `HKCU\\Software\\Classes\\Drive\\shell\\OpenInWSL\\command` | `(default)` | REG_SZ | `"...\wt.exe" -p "Ubuntu" -d "%1"` |
| `HKCU\\Software\\Classes\\Directory\\Background\\shell\\OpenInWSL\\command` | `(default)` | REG_SZ | `"...\wt.exe" -p "Ubuntu" -d "%V"` |
| `HKCU\\Software\\Classes\\Directory\\shell\\OpenInWSL\\command` | `(default)` | REG_SZ | `"...\wt.exe" -p "Ubuntu" -d "%1"` |
"""
