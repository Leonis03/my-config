# WSL PATH 白名单相关对话摘录

来源文件: `C:\Users\<your-windows-user>\move\conversations.json`

说明:
- 这是从 `conversations.json` 中整理出的相关对话摘录。
- 只保留了用户与助手的关键轮次。
- 工具调用、搜索中间态、空白 system/tool 节点已省略。

## 对话 1

- 标题: `Branch · npm pnpm relationships`
- 会话 ID: `<conversation-id>`

### 2026-02-17 User

我可以设置不混入Windows PATH，但是保留调用Windows路径/进程的能力吗？

### 2026-02-17 Assistant

可以，而且这正是 **`wsl.conf` 的标准用法**：把 Windows 的 PATH **不再追加进 Linux 的 `$PATH`**，但 **仍保留 WSL 启动 Windows 进程（interop）的能力**。

#### 做法：关掉追加 PATH，但保留 interop

在你的 WSL 发行版里编辑 `/etc/wsl.conf`（没有就新建）：

```ini
[interop]
enabled=true
appendWindowsPath=false
```

- `enabled=true`：WSL 仍“支持启动 Windows 进程”
- `appendWindowsPath=false`：WSL 不再把 Windows 的 PATH 元素加到 `$PATH` 里

改完要重启 WSL 才会生效（PowerShell 里）：

```powershell
wsl --shutdown
```

#### 关掉 Windows PATH 后，还能怎么“从 WSL 调 Windows 程序”？

Interop 这条能力还在，只是 **你不会再“自动找到”那些 .exe**，因为 Windows 目录不在 `$PATH` 里了。

所以通常改成下面两种调用方式之一：

**A) 用完整路径调用（最稳）**

```bash
/mnt/c/Windows/System32/notepad.exe
/mnt/c/Windows/explorer.exe .
/mnt/c/Windows/System32/cmd.exe /C dir
```

**B) 给常用 Windows 程序做 alias（省打字）**

```bash
echo "alias explorer='/mnt/c/Windows/explorer.exe'" >> ~/.bashrc
echo "alias cmd='/mnt/c/Windows/System32/cmd.exe'" >> ~/.bashrc
source ~/.bashrc
```

#### 验证思路

```bash
printf '%s\n' "$PATH" | tr ':' '\n' | grep -E '^/mnt/[a-z]/' || echo "OK: no Windows PATH"
/mnt/c/Windows/System32/cmd.exe /C echo hello
```

### 2026-02-17 User

我是在下面加三行吗？

```ini
[interop]
enabled = true
appendWindowsPath = false
```

### 2026-02-17 Assistant

对，就是在这个文件里 **另起一个 `[interop]` 小节**（不要塞进 `[user]` 下面当成缩进内容）。

```ini
[interop]
enabled=true
appendWindowsPath=false
```

`appendWindowsPath` 这项就是专门控制“是否把 Windows 的 PATH 追加进 Linux 的 `$PATH`”。

改完后建议验证两件事：

1. Windows PATH 不再混入

```bash
printf '%s\n' "$PATH" | tr ':' '\n' | grep -E '^/mnt/[a-z]/' || echo "OK: no Windows PATH"
```

2. 仍能跑 Windows 进程

```bash
/mnt/c/Windows/System32/cmd.exe /C echo hello
```

## 对话 2

- 标题: `npm pnpm relationships`
- 会话 ID: `<conversation-id>`

### 2026-02-18 Assistant

整体来说：**Codex 这套做法“算规范”，而且逻辑跟 WSL 的设计是对齐的**。

你设的：

```ini
[interop]
enabled=true
appendWindowsPath=false
```

这正是“不要 PATH 串味，但保留 interop 能力”的官方开关组合。

不过，如果追求更“最小化影响面”，更推荐：

- 不把 `/mnt/c/Windows/System32` 这种大目录塞回 PATH
- 只给少量命令做 alias

推荐形态：

```bash
alias explorer.exe='/mnt/c/Windows/explorer.exe'
alias clip.exe='/mnt/c/Windows/System32/clip.exe'
alias pwsh.exe='/mnt/c/Program\ Files/PowerShell/7/pwsh.exe'
alias Code.exe='/mnt/c/Program\ Files/Microsoft\ VS\ Code/Code.exe'
```

同时指出：

- VS Code 更主流的姿势其实是 `code .`
- `pnpm setup` 能用，但会让版本来源更复杂

### 2026-02-18 User

写English prompt，复原.bashrc，用alias的explorer.exe clip.exe pwsh.exe和`code .`

### 2026-02-18 Assistant

下面这段英文 prompt 可以直接丢给 Codex/任何“会动你机器”的 AI，让它**把 `.bashrc` 里那段手动追加 Windows PATH 的逻辑撤掉**，改成 **alias 方式**，并把 VS Code 的使用方式切回官方推荐的 `code .`（Remote-WSL）。

```text
You are working inside my WSL (Ubuntu) as user "<your-linux-user>". I have already set /etc/wsl.conf:
  [interop]
  enabled=true
  appendWindowsPath=false
Goal: keep Windows interop enabled, but DO NOT add any Windows directories to $PATH. Instead, expose a few Windows tools via bash aliases only: explorer.exe, clip.exe, pwsh.exe. For VS Code, I want to use the official Remote-WSL workflow via `code .` (NOT by adding Windows Code.exe to PATH).

Please do the following carefully:

1) Backup files first:
   - cp -a ~/.bashrc ~/.bashrc.bak.$(date +%Y%m%d-%H%M%S)
   - if ~/.bash_aliases exists: cp -a ~/.bash_aliases ~/.bash_aliases.bak.$(date +%Y%m%d-%H%M%S)

2) Edit ~/.bashrc:
   - Remove any block that appends Windows directories to PATH when running under WSL.
   - Specifically delete the block that starts with a comment similar to:
       "# WSL: keep selected Windows executables available when appendWindowsPath=false"
     and ends with its matching "fi".
   - Do NOT change other unrelated content (e.g., my nvm and PNPM_HOME sections).

3) Add WSL-only aliases (preferred location: ~/.bash_aliases, create the file if missing):
   - Add a guarded block that only runs in WSL, e.g. detect WSL via /proc/version or $WSL_DISTRO_NAME.
   - Define these aliases using full paths (handle spaces safely by quoting):
       alias explorer.exe='/mnt/c/Windows/explorer.exe'
       alias clip.exe='/mnt/c/Windows/System32/clip.exe'
       alias pwsh.exe='/mnt/c/Program Files/PowerShell/7/pwsh.exe'
   - Do NOT add /mnt/c/Windows, /mnt/c/Windows/System32, or any "Program Files" directory to $PATH.

4) VS Code behavior:
   - Do NOT add Windows "Code.exe" to PATH and do NOT create an alias to it.
   - I want `code .` to work using VS Code Remote - WSL.
   - Check whether `command -v code` works in WSL.
     * If it works: keep it.
     * If it does NOT work: print concise instructions to fix it on the Windows side:
       - Install VS Code on Windows and ensure "Add to PATH" is enabled during install
       - Install the VS Code "WSL" extension
       - Restart the WSL terminal, then retry `code .`
     Do not attempt to install Windows VS Code inside WSL.

5) Reload and validate:
   - source ~/.bashrc (or exec bash)
   - Confirm Windows paths are NOT in $PATH:
       printf '%s\n' "$PATH" | tr ':' '\n' | grep -E '^/mnt/[a-z]/' && echo "ERROR: Windows paths still present" || echo "OK: no Windows paths in PATH"
   - Confirm aliases work:
       type explorer.exe
       type clip.exe
       type pwsh.exe
       echo "hello from wsl" | clip.exe
       pwsh.exe -NoProfile -Command '$PSVersionTable.PSVersion'
   - Confirm VS Code workflow:
       mkdir -p ~/tmp/vscode-test && cd ~/tmp/vscode-test
       code .

6) Show me what changed:
   - Provide a unified diff between the backup and the new files:
       diff -u ~/.bashrc.bak.* ~/.bashrc || true
       (and for ~/.bash_aliases if modified)
   - If anything fails, restore from the backups and report the error clearly.
```

### 2026-02-18 User

你的prompt有把alias放进 `~/.bash_aliases`吗？

### 2026-02-18 Assistant

有的。

那段 prompt 明确写了：

- preferred location: `~/.bash_aliases`
- create the file if missing

也就是优先改 `~/.bash_aliases`，没有就创建。

### 2026-02-18 Assistant

整体来说，Codex 的“备份 → 改动 → 验证 → 失败就回滚”这个流程是规范的，但它这次“验证失败”的原因，大概率**不是** `.bashrc` 改坏了，而是踩到了更底层的 WSL interop/vsock 问题。

核心判断：

- `appendWindowsPath=false` 会让 `code` 消失，这是预期副作用
- 更干净的目标形态是：
  - `/etc/wsl.conf` 保持 `appendWindowsPath=false`
  - 不在 `.bashrc` 里注入一坨 Windows PATH
  - 把 alias 放在 `~/.bash_aliases`
  - `code .` 采用两种方案之一

推荐写法：

```bash
if grep -qi microsoft /proc/version 2>/dev/null; then
  alias explorer.exe='/mnt/c/Windows/explorer.exe'
  alias clip.exe='/mnt/c/Windows/System32/clip.exe'
  alias pwsh.exe='/mnt/c/Program Files/PowerShell/7/pwsh.exe'
fi
```

`code .` 两种方案：

**方案 A：只加 VS Code bin 这一条 PATH**

```bash
if grep -qi microsoft /proc/version 2>/dev/null; then
  VSCODE_BIN="/mnt/c/Users/<your-windows-user>/AppData/Local/Programs/Microsoft VS Code/bin"
  case ":$PATH:" in
    *":$VSCODE_BIN:"*) : ;;
    *) [ -d "$VSCODE_BIN" ] && export PATH="$PATH:$VSCODE_BIN" ;;
  esac
fi
```

**方案 B：不给 PATH，直接给 `code` 做 alias**

```bash
if grep -qi microsoft /proc/version 2>/dev/null; then
  alias code='/mnt/c/Users/<your-windows-user>/AppData/Local/Programs/Microsoft VS Code/bin/code'
fi
```

### 2026-02-18 User

写prompt。`code .`方案A。

### 2026-02-18 Assistant

下面这份是给 Codex 的 **英文 prompt**，目标是：

- 保持 `/etc/wsl.conf` 里的

```ini
[interop]
enabled=true
appendWindowsPath=false
```

- 不重新开启 Windows PATH 注入
- `explorer.exe`、`clip.exe`、`pwsh.exe` 走 alias
- `code .` 走方案 A：**只把 VS Code 的 `bin` 目录加回 PATH**

关键要求包括：

1. 先备份 `~/.bashrc` 和 `~/.bash_aliases`
2. 删除旧的 WSL PATH injection block
3. 确保 `~/.bashrc` 会 source `~/.bash_aliases`
4. 在 `~/.bash_aliases` 中加入：

```bash
alias explorer.exe='/mnt/c/Windows/explorer.exe'
alias clip.exe='/mnt/c/Windows/System32/clip.exe'
alias pwsh.exe='/mnt/c/Program Files/PowerShell/7/pwsh.exe'
```

5. 只允许下面这些 VS Code `bin` 候选路径之一进入 PATH：

```text
/mnt/c/Users/<your-windows-user>/AppData/Local/Programs/Microsoft VS Code/bin
/mnt/c/Program Files/Microsoft VS Code/bin
/mnt/c/Program Files (x86)/Microsoft VS Code/bin
```

6. 只做命令解析验证，不实际执行 Windows `.exe`

### 2026-02-18 Assistant

最后的判断是：

- 这次做法符合你的目标
- `appendWindowsPath=false` 下不再混入整坨 Windows PATH
- 少数 Windows 命令通过 alias 暴露
- `code .` 通过 Plan A 仅加入 VS Code 的 `bin`

同时建议把验证逻辑从“全禁 `/mnt/c`”改成更贴近目标的 allowlist：

```bash
printf '%s\n' "$PATH" | tr ':' '\n' | grep -E '^/mnt/c/' || echo "OK: no Windows paths"
printf '%s\n' "$PATH" | tr ':' '\n' | grep -E '^/mnt/c/Windows($|/System32$)' && echo "ERROR: Windows dirs leaked into PATH"
```

## 结论摘录

从这些对话里，可以归纳出你和 GPT 达成的一致策略是：

1. WSL 保留 interop，但关闭 Windows PATH 自动继承

```ini
[interop]
enabled=true
appendWindowsPath=false
```

2. Windows 程序不靠“整段 Windows PATH 注入”，而是靠人工白名单
   - `explorer.exe`
   - `clip.exe`
   - `pwsh.exe`

3. alias 优先放在 `~/.bash_aliases`

4. `code .` 不走 broad Windows PATH
   - 优先走 Plan A：只把 VS Code 的 `bin` 加回 PATH
   - 或者对 `code` 单独做 alias

5. 验证时应避免把“Windows exe 在特定上下文跑不起来”的底层问题，误判成 `.bashrc` / alias 配置问题
