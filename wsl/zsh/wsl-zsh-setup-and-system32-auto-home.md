# WSL (Ubuntu) System32 自动转 ~ 与 Zsh 环境完整配置指南

本文档介绍在 WSL (Ubuntu) 环境下，如何配置 **初始 System32 路径自动跳转到 Ubuntu 用户家目录（`~`）**、安装与配置 **Zsh + Oh My Zsh**、无缝迁移原版 **`.bashrc` 环境变量与工具链**，以及安装 **`zsh-autosuggestions` 历史自动建议插件**。

---

## 一、 背景与常见问题

1. **为什么 WSL 会启动在 System32？**
   * 当在 Windows Terminal 中打开 WSL 标签页时，若 Windows Terminal 继承了 Windows 管理员环境路径，WSL 的初始挂载工作目录会变成 `/mnt/c/Windows/System32` 或 `/mnt/c/Windows/SysWOW64`。
2. **为什么安装 Oh My Zsh 后许多命令丢失（`command not found`）？**
   * 安装 Oh My Zsh 后，默认 Shell 会切换为 Zsh，并生成全新的 `~/.zshrc` 文件。
   * 之前安装在 `~/.bashrc` 中的环境变量（如 **NVM / Node.js**、**PNPM**、**Antigravity CLI (`agy`)**、**Proxy 代理配置** 等）不会被 Zsh 自动读取。
   * **解决方案**：将原版 `~/.bashrc` 的环境变量迁移至 `~/.zshrc`，并加入大小写不敏感的 System32 检测跳转逻辑。

---

## 二、 完整配置步骤与 Bash 命令

以下命令均在 **WSL Ubuntu 终端** 中执行。

### 1. 安装 Zsh 及必要依赖

```bash
sudo apt update && sudo apt install -y zsh git curl
```

---

### 2. 安装 Oh My Zsh（无人值守静默安装）

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
```

---

### 3. 安装 `zsh-autosuggestions` 插件

克隆插件到 Oh My Zsh 自定义插件目录：

```bash
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
```

---

### 4. 配置 `~/.zshrc`（启用插件 + 自动转 ~ + 迁移环境变量）

运行以下脚本，一键完成插件启用、System32 自动跳转与原 `.bashrc` 工具链环境迁移：

```bash
# 1. 启用 zsh-autosuggestions 插件
sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions)/g' ~/.zshrc

# 2. 追加 System32 检测与工具环境变量
cat << 'EOF' >> ~/.zshrc

# ==============================================================================
# 1. WSL: Avoid Windows system directories (System32 / SysWOW64) on startup
# ==============================================================================
if [[ "${PWD:l}" =~ ^/mnt/[a-z]/windows/(system32|syswow64) ]]; then
  cd ~
fi

# ==============================================================================
# 2. User Environment Variables & Toolchains (Migrated from .bashrc)
# ==============================================================================

# NVM / Node.js
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# PNPM
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac

# Antigravity CLI (agy) & User Local Bin
export PATH="$HOME/.local/bin:$PATH"

# Proxy Configuration (e.g. Clash Verge Rev)
export ALL_PROXY=socks5h://127.0.0.1:<proxy-port>
export HTTPS_PROXY=http://127.0.0.1:<proxy-port>
export HTTP_PROXY=http://127.0.0.1:<proxy-port>

# WSL VS Code Launcher Integration
if grep -qi microsoft /proc/version 2>/dev/null; then
  for d in \
    "/mnt/c/Users/<your-windows-user>/AppData/Local/Programs/Microsoft VS Code/bin" \
    "/mnt/c/Users/<your-windows-user>/AppData/Local/Programs/Microsoft VS Code/bin" \
    "/mnt/c/Program Files/Microsoft VS Code/bin" \
    "/mnt/c/Program Files (x86)/Microsoft VS Code/bin"; do
    if [ -d "$d" ]; then
      case ":$PATH:" in *":$d:"*) ;; *) export PATH="$PATH:$d" ;; esac
    fi
  done
fi
export BROWSER=wslview
EOF
```

---

### 5. 将 Zsh 设为默认 Shell 并立即生效

```bash
# 切换当前用户的默认 Shell 为 Zsh
chsh -s $(which zsh)

# 重新加载配置
source ~/.zshrc
```

---

## 三、 `zsh-autosuggestions` 常用按键速查

`zsh-autosuggestions` 会根据命令历史在光标后呈现灰色幽灵文字（Ghost Text），常用操作如下：

| 按键组合 | 对应动作 | 行为说明 |
| :--- | :--- | :--- |
| **`→` (右方向键)** | 全量采纳 | 在行尾按下时，**一键采纳整条灰色建议**并移至行尾。 |
| **`End`** | 全量采纳 | 跳至行尾并采纳整条建议。 |
| **`Ctrl + E` / `Ctrl + F`** | 全量采纳 | Emacs 模式下的行尾跳跃/前进字符，触发整条采纳。 |
| **`Alt + F`** 或 **`Alt + →`** | 逐词采纳 | **只采纳建议中的下一个单词/参数**（方便快速修改参数）。 |
| **继续输入字符 / `Backspace`** | 取消建议 | 当输入内容与建议不匹配时，灰色提示自动清除。 |

---

## 四、 核心机制原理解析

### 1. 为什么 `${PWD:l}` 判定不会影响日常手动 `cd`？
* `~/.zshrc` 是 Shell 的**启动初始化脚本**，仅在**创建新标签页/新终端会话的那一瞬间**运行一次。
* 打开终端后，日常手动执行 `cd /mnt/c/Windows/System32` 属于命令交互，**不会重新执行 `.zshrc`**，因此正常停留在该目录，不会被误弹回。

### 2. 为什么使用 `${PWD:l}` 与正则匹配？
* `${PWD:l}`（或 Bash 下的 `${PWD,,}`）将当前路径转为全小写，避免 Windows 盘符与路径大小写不一致（如 `/mnt/c/WINDOWS/System32` vs `/mnt/c/windows/system32`）导致判断失效。
* 正则 `^/mnt/[a-z]/windows/(system32|syswow64)` 兼容所有盘符（如 `C:`、`D:` 盘）及 32/64 位 Windows 系统目录。\n