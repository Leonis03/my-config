# WSL 环境复刻指南

> **用途**：在一台**全新的 Windows 机器**上，从零搭出与台式机（`<your-linux-user>@Ubuntu-24.04`）等价的 WSL2 开发环境。
>
> **使用方式**：可以人工照做，也可以把本文件整个发给 AI Agent（Claude Code / Antigravity / Codex），让它按步骤执行并汇报验证结果。
>
> **本文以 Ubuntu 24.04 为基准**，它是此前的主力发行版。日常工作现已转到 Fedora 44，配置正在向它对齐；
> 步骤本身大多通用，**发行版特定的差异单独记在** [`../distro-differences.md`](../distro-differences.md)
> 第四节（包名、`chsh`、系统骨架、corepack、wslu 缺失、fcitx5 绕路），照本文做 Fedora 时对照那一节。

**参考环境（2026-09-20 实测）**

| 项 | 值 |
| :--- | :--- |
| 发行版 | Ubuntu 24.04.4 LTS (noble) |
| WSL | 2.7.14.0（`release/2.7` 加固轨） |
| 内核 | 6.18.33.2-microsoft-standard-WSL2 |
| 默认 Shell | zsh 5.9 + oh-my-zsh（主题 `robbyrussell`，插件 `git` `zsh-autosuggestions`） |
| apt 源 | 清华 TUNA 镜像 |
| 工具链 | git 2.55.0（git-core PPA）· gh 2.93.0 · node v24.21.0 (nvm 0.40.4) · pnpm 11.27.0 · uv 0.12.5 (Python 3.12) |
| 互操作 | `appendWindowsPath=false` + 显式函数桥接 |

---

## 一、本目录内容

`files/` 存放可直接复制的配置文件**原件**（已脱敏，不含任何凭据）：

| 仓库中的文件 | 部署到 | 作用 |
| :--- | :--- | :--- |
| `files/wslconfig` | **Windows 家目录**的 `%USERPROFILE%\.wslconfig` | **整个 WSL2 虚拟机**一份，不在发行版里。网络模式、代理继承、DNS、内存/CPU/swap 上限。见步骤 0 |
| `files/wsl.conf` | `/etc/wsl.conf` | **每个发行版各一份**。systemd、默认用户、互操作策略、挂载策略 |
| `files/fstab` | 追加到 `/etc/fstab` | 显式挂载 C/D/E 三个固定盘（U 盘故意不挂，见步骤 1） |
| `files/systemd/wsl-binfmt-guard.service`<br>`files/systemd/wsl-binfmt-guard.timer` | `/etc/systemd/system/` | 互操作 binfmt 守护。**多发行版机器必装**，见步骤 1.3 |
| `files/systemd/systemd-binfmt-no-unregister.conf` | `/etc/systemd/system/systemd-binfmt.service.d/no-unregister.conf` | 阻止发行版优雅关机时清空全局 binfmt 表 |
| `files/systemd/wsl-mount-guard.service`<br>`files/systemd/wsl-mount-guard.timer` | `/etc/systemd/system/` | `/mnt/wsl` 共享 bind 守护。另一个发行版优雅关机会把你的 bind 传播式卸载掉，见步骤 1.4 |
| `files/bin/wslview` | `~/.local/bin/wslview` | **仅在没有 wslu 的发行版上需要**（如 Fedora）。`BROWSER` 必须指向真实可执行文件，不能是 shell 函数，见 [`../distro-differences.md`](../distro-differences.md) 第四节 |
| `files/shell_common` | `~/.shell_common` | **bash 与 zsh 共用**的环境变量、PATH、代理、输入法、keyring |
| `files/shell_wslfn` | `~/.shell_wslfn` | Windows 互操作**函数**定义。除末尾 export 一个 `BASH_ENV` 指回自己（给非交互 bash 用）外无副作用，所以够轻，敢从 `~/.zshenv` 里 source |
| `files/zshenv` | `~/.zshenv` | 每次 zsh 启动都会读，**包括非交互**（脚本 / AI Agent） |
| `files/zshrc` | `~/.zshrc` | zsh 专有：oh-my-zsh、主题、PROMPT |
| `files/bashrc` | `~/.bashrc` | bash 专有：PS1、历史、补全 |
| `files/profile` | `~/.profile` | 登录 shell 入口 |

> 配置文件内的注释一律使用**纯 ASCII 英文**，避免跨机器、跨终端的编码问题。

---

## 二、配置分层设计（先理解，再动手）

这是本环境与「把所有东西堆进 `.bashrc`」最大的区别。四层，各司其职：

```
~/.zshenv          每次 zsh 启动都读（含非交互）-> 只放函数定义，必须轻量
   |
   +-> ~/.shell_wslfn      Windows 互操作函数（explorer / cmd / reg / powershell ...）
                             |    ^
                             |    | 也被 shell_common 引用
                             +--> export BASH_ENV=$HOME/.shell_wslfn
                                  bash 没有 .zshenv 的对等物，这是非交互 bash
                                  唯一的入口（`bash -c` / `#!/bin/bash` 脚本）
~/.zshrc  --+                     |
            +--> ~/.shell_common --+   环境变量、PATH、代理、输入法、keyring
~/.bashrc --+                          （bash 与 zsh 的唯一真相来源）
```

### 三条硬规则

1. **只有两边都合法的语句才能进 `~/.shell_common`。**
   - oh-my-zsh / `ZSH_THEME` / `PROMPT` / `zstyle` -> 只能进 `~/.zshrc`
   - `PS1` / `shopt` / `HISTCONTROL` / bash-completion -> 只能进 `~/.bashrc`
   - `${PWD,,}` 是 bash 专有、`${PWD:l}` 是 zsh 专有，共用文件里一律改用 `tr` 转小写

2. **`conda init` 块绝不共用。** 两个 shell 的 hook 不同（`shell.zsh` vs `shell.bash`），必须各写各的。

3. **用函数，不要用 alias。**
   非交互 shell **默认不展开 alias**（bash 和 zsh 都一样）。这意味着 `alias cmd=...` 对脚本、cron、AI Agent 全部无效。函数则在任何模式下都有效。
   这也是 `~/.zshenv` 存在的唯一理由——它是非交互 zsh 会读的**唯一**启动文件。

> **为什么值得较真**：`gh auth login` 会起子 shell 调浏览器，alias 不传递，授权页面永远打不开。详见 [`../../git-github/README.md`](../../git-github/README.md) 第二节。

---

## 三、执行步骤

### 步骤 0：Windows 侧安装 WSL2 + Ubuntu 24.04

在 Windows PowerShell（管理员）中执行：

```powershell
wsl --install -d Ubuntu-24.04
wsl --set-default-version 2
```

首次启动会要求创建 Linux 用户名与密码。本参考环境用户名记作 `<your-linux-user>`。

#### 0.1 部署 `.wslconfig`（**别跳过，它决定后面代理能不能通**）

这个文件在 **Windows 家目录**，管的是整个 WSL2 虚拟机，和发行版里的 `/etc/wsl.conf` 是两回事：

```bash
# 路径要运行时问 Windows 要，别写死账户名（见「常见问题」里 drvfs 大小写那条）
WIN_HOME=$(wslpath -u "$(cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /c 'echo %USERPROFILE%' \
  < /dev/null 2>/dev/null | tr -d '\0\r')")
cp files/wslconfig "$WIN_HOME/.wslconfig"
```

然后在 Windows 侧 `wsl --shutdown`，VM 重建后才生效。

**为什么它是步骤 0 而不是可选项**：`networkingMode=mirrored` 让 Windows 的 `127.0.0.1` 在 WSL 里就是同一个 `127.0.0.1`，这正是步骤 4 里 `~/.shell_common` 敢把 `host_ip` 写死成 `127.0.0.1` 的唯一依据。用默认的 NAT 模式时宿主是另一个地址，`127.0.0.1` 指向 WSL 自己，所有走代理的请求都会 connection refused——而报错离这个文件很远，`~/.shell_common` 里没有任何线索指向它。

`memory` / `processors` / `swap` 是按本机（16 GB 内存、12 逻辑处理器）定的，**换机器要重算**，别照抄。不写这个文件的默认值是「50% 物理内存 + 全部逻辑处理器」。

> 若需要把 WSL 发行版迁移到非系统盘，见 [`../storage/wsl-distro-move-to-d-drive.md`](../storage/wsl-distro-move-to-d-drive.md)。

---

### 步骤 1：配置 `/etc/wsl.conf`（需 sudo）

#### 1.1 `/etc/wsl.conf`

```bash
sudo cp files/wsl.conf /etc/wsl.conf
sudo sed -i 's|<your-linux-user>|'"$USER"'|' /etc/wsl.conf
cat /etc/wsl.conf
```

**`appendWindowsPath=false` 解决什么问题**：Windows PATH 通常有几十上百个目录，注入后会导致补全卡顿、磁盘扫描变慢，而且 `find` / `sort` / `curl` 等同名命令会被 Windows 版本抢先。关掉之后 PATH 保持纯净，只显式桥接真正需要的几个命令。

**代价**：所有 `.exe` 不再能裸名调用，必须用绝对路径——这正是步骤 3 的函数要解决的。

#### 1.2 `/etc/fstab`：只挂 C/D/E，且可写

```bash
sudo mkdir -p /mnt/c /mnt/d /mnt/e     # automount 关掉后 WSL 不再替你建挂载点
cat files/fstab | sudo tee -a /etc/fstab
```

**为什么关掉 automount**：WSL 会持有它自动挂载的可移动介质，U 盘一旦被挂上，**Windows 就弹不出来，除非 `wsl --shutdown`**。改成 fstab 显式列举固定盘，其它盘符一律不碰。临时要用某个 U 盘，现用现挂（命令写在 `files/fstab` 的注释里），**弹出前记得 `umount`**。

**为什么不再加 `ro`**：早期版本给 `/mnt` 加了 `ro`，目的是防 AI Agent 手滑 `rm -rf`。后来取消了，理由是它**根本没起到防护作用**——

```bash
rm /mnt/c/Users/<user>/Desktop/x.txt              # EROFS，失败
powershell Remove-Item C:\Users\<user>\Desktop\x.txt   # 成功
```

第二条走的正是 `~/.shell_wslfn` 里**我们有意保留**的互操作桥接。所以 `ro` 挡得住手滑，挡不住 Agent；代价却是一堆正常的 Windows 相关命令以 EROFS 的形式怪异失败。**防事故改由 git 提交纪律承担**：动 Agent 之前先 commit，出事 `git reset --hard`。

> 如果你确实需要那套只读加固（比如跑不可信代码的机器），做法完整保留在
> [`../../agent/skills/wsl-windows-command/references/hardened-mounts.md`](../../agent/skills/wsl-windows-command/references/hardened-mounts.md)。

#### 1.3 互操作 binfmt 守护（**多发行版机器必装**）

只装了一个发行版可以跳过。装了两个及以上，这一步是必需的：

```bash
sudo cp files/systemd/wsl-binfmt-guard.service files/systemd/wsl-binfmt-guard.timer \
  /etc/systemd/system/
sudo mkdir -p /etc/systemd/system/systemd-binfmt.service.d
sudo cp files/systemd/systemd-binfmt-no-unregister.conf \
  /etc/systemd/system/systemd-binfmt.service.d/no-unregister.conf
sudo systemctl daemon-reload
sudo systemctl enable --now wsl-binfmt-guard.timer
```

**为什么需要**：`binfmt_misc` 是 **WSL 虚拟机内核全局的**，所有发行版共用一张注册表。
`wsl --terminate <另一个发行版>` 会把 `WSLInterop` 处理器**给所有发行版一起摘掉**，而且没有任何东西会把它装回来。症状是刚才还好好的 Windows 命令突然报 `exec format error`，且看不出和你刚停掉的那个发行版有任何关系。

更麻烦的是**自救悖论**：`WSLInterop` 一没，`wsl.exe` 本身就是个 Windows 程序，跑不起来——你没法用互操作去修互操作。所有恢复手段必须是发行版内部的。应急单行命令：

```bash
sudo systemctl restart systemd-binfmt
```

> **这条应急命令在装了 timer 的机器上多半用不到，而且单独用会骗人。** `systemd-binfmt.service`
> 被 `ConditionDirectoryNotEmpty` 门控在五个 `binfmt.d` 目录上；这些目录默认全空，unit 会被直接
> 跳过，WSL 注入的那个 generator drop-in 根本没机会执行，但 `systemctl restart` 照样返回 0。
> 实测：目录为空时重启毫无作用，手工放一个 `/etc/binfmt.d/WSLInterop.conf` 之后同一条命令立刻
> 生效。装了 `wsl-binfmt-guard.timer` 就别折腾这些——先 `systemctl list-timers` 等满一个 30 秒
> 周期。断了之后 30 秒内连敲三条命令就断定机器坏了，是这里最容易犯的错。

#### 1.4 `/mnt/wsl` 跨发行版共享守护（**装了 1.3 就一起装**）

```bash
sudo cp files/systemd/wsl-mount-guard.service files/systemd/wsl-mount-guard.timer \
  /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wsl-mount-guard.timer
```

**为什么需要**：`files/fstab` 里那条 `/ /mnt/wsl/<Distro> none bind,nofail 0 0` 只保证**本发行版
开机**时把共享恢复。`/mnt/wsl` 是所有发行版共用的 tmpfs，挂载传播是双向的——**另一个发行版优雅
关机**时，它的 systemd 会卸载自己命名空间里那些传播过去的副本，卸载再传播回来，把你这边的原始
bind 一起带走，而且在你下次重启前没有任何东西会恢复它。

`wsl --terminate` 不会触发这个：硬杀不走优雅卸载路径，和 `no-unregister.conf` 注释里区分的是同一条
界线。要主动复现，用 `wsl.exe -d <另一个发行版> -u root -e systemctl poweroff`。

实测一轮：poweroff 后 T+10s 共享消失，T+20s 被 timer 恢复，此后稳定。守护的目标是从 `/etc/fstab`
里读出来的（凡 target 在 `/mnt/wsl/` 下的条目），所以同一份 unit 文件在每个发行版都能直接用，不需要
按发行版替换名字。

> **生效方式**：在 Windows PowerShell 执行 `wsl.exe --shutdown`，然后重新打开 WSL。改 `wsl.conf` / `fstab` 后不 shutdown 不生效。注意 `--shutdown` 会关掉**所有**发行版。

---

### 步骤 2：apt 换源 + 基础包

```bash
# 备份原源
sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak

# 换清华 TUNA 镜像（国内必要，否则后续都很慢）
sudo sed -i 's|http://archive.ubuntu.com/ubuntu/|https://mirrors.tuna.tsinghua.edu.cn/ubuntu/|g; s|http://security.ubuntu.com/ubuntu/|https://mirrors.tuna.tsinghua.edu.cn/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources

sudo apt update && sudo apt upgrade -y
sudo apt install -y zsh curl wget build-essential wslu git-filter-repo
```

`wslu` 提供 `wslview`，是 `gh auth login` 能唤起 Windows 浏览器的前提。

**较新版本的 git（可选但推荐）**。Ubuntu 24.04 自带 git 2.43.0（2023 年 11 月），落后主线较多：

```bash
sudo add-apt-repository -y ppa:git-core/ppa
sudo apt update && sudo apt install -y --only-upgrade git
git --version   # 预期 2.55.0 或更高
```

> **注意**：PPA 会**替换**系统同名包（仍装在 `/usr/bin/git`），不是并存。此后 git 的安全更新由 PPA 维护者负责，不再是 Ubuntu 安全团队。这与 uv 管理 Python 的「旁路一套、不碰系统原版」是相反的策略——git 可以这样做是因为几乎没有系统组件依赖特定 git 版本。

---

### 步骤 3：zsh + oh-my-zsh

```bash
# oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# zsh-autosuggestions 插件
git clone https://github.com/zsh-users/zsh-autosuggestions \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"

# 设为默认 shell
chsh -s "$(which zsh)"
```

---

### 步骤 4：部署 shell 配置（核心步骤）

```bash
cd <本仓库>/wsl/setup

# 先备份现有配置
mkdir -p ~/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)
cp ~/.zshrc ~/.bashrc ~/.profile ~/.dotfiles-backup/*/ 2>/dev/null || true

# 部署四层
cp files/shell_common ~/.shell_common
cp files/shell_wslfn  ~/.shell_wslfn
cp files/zshenv       ~/.zshenv
cp files/zshrc        ~/.zshrc
cp files/bashrc       ~/.bashrc
cp files/profile      ~/.profile
```

**部署后必须按本机情况调整 `~/.shell_common`：**

| 位置 | 需要确认的内容 |
| :--- | :--- |
| 第 5 节 Proxy | 代理端口填 `<proxy-port>`（Clash Verge Rev）。不用代理就把整节注释掉 |
| VS Code 路径探测 | 候选列表含 `$USER` 与一个占位符，换机器可能要加自己的 Windows 用户名 |
| 第 8 节 keyring | 仅 Antigravity CLI 需要；不用可删 |

**凭据不要写进这些文件。** 需要环境变量形式的 token 时：

```bash
touch ~/.shell_secrets && chmod 600 ~/.shell_secrets
echo 'export SOME_TOKEN=xxx' >> ~/.shell_secrets
```

`~/.shell_common` 末尾会自动 source 它，而它永远不进版本库。

---

### 步骤 5：工具链

```bash
# nvm + Node（动态解析 nvm 官方最新版本安装，失败时保底 v0.40.8）
NVM_URL=$(curl -fsSLI -o /dev/null -w "%{url_effective}" https://github.com/nvm-sh/nvm/releases/latest)
NVM_VER="${NVM_URL##*/}"
curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VER:-v0.40.8}/install.sh" | bash
exec zsh
nvm install --lts          # 参考环境为 v24.21.0
npm i -g npm@latest

# pnpm（PNPM_HOME 已在 shell_common 中定义，推荐独立脚本或 npm 安装，避免使用 corepack）
curl -fsSL https://get.pnpm.io/install.sh | sh -
# 或: npm install -g pnpm

# uv（Python 包管理与隔离，全局固定 3.12）
curl -LsSf https://astral.sh/uv/install.sh | sh
mkdir -p ~/.config/uv && echo "3.12" > ~/.config/uv/.python-version
```

> **Python 约定**：系统 `/usr/bin/python3` 严格保留给 OS 包，日常一律 `uv run --python 3.12`。无需也不默认安装 Anaconda/Miniconda，Python 包与虚拟环境全部由 `uv` 统一管理。与 git 用 PPA 就地升级不同，Python 必须走旁路隔离——大量 Ubuntu 组件依赖系统 Python，换掉会连锁炸掉 apt。

#### 版本选择：两个刻意不升的决定

**Node 版本管理器留在 nvm，不换 fnm。**

fnm 用 Rust 写，确实更快，但快得有限：实测 zsh 启动开销 nvm +75ms vs fnm +15ms，切换版本 180ms vs 12ms。**每开一个 shell 省 70ms**，不是网上说的"快一个数量级"。

真正的否决理由是架构冲突：**fnm 依赖 shell hook 激活（`--use-on-cd`），生成非交互 shell 的工具会错过它，然后静默回退到另一个 Node**。这正是本配置第二节"三条硬规则"第 3 条要绕开的那类坑——`~/.zshenv` 存在的唯一理由就是让非交互 shell 也能工作，全是为了 AI Agent。换 fnm 等于把这个坑原样搬回来。

**但别以为现状就没有这个问题——它只是轻一些。**

nvm 只在 `~/.shell_common` 里加载，而 `~/.zshenv` 只 source `~/.shell_wslfn`（函数）。所以 node 进 PATH 靠的是**交互 shell**，非交互 shell 只是**从交互祖先继承**了 PATH 才看起来能用。

验证必须用 `env -i` 切断继承，否则会假阳性（2026-09-20 实测）：

```bash
zsh -c 'command -v node'                                          # 有输出 -- 但这是继承来的，不算数
env -i HOME=$HOME TERM=xterm /usr/bin/zsh -ic 'command -v node'   # 有输出：交互 shell 正常
env -i HOME=$HOME TERM=xterm /usr/bin/zsh -c  'command -v node'   # 【无输出】
```

第三条无输出，意味着**由 systemd、`wsl.exe -e`、或任何不继承交互环境的方式拉起的 agent 拿不到 node**。两个发行版上都成立。

> **这是个尚未决定的设计问题，不是 bug 报告。** 要修就是把 PATH 相关的部分从 `shell_common`
> 提到 `~/.zshenv`，但那会让 `~/.zshenv` 变重，与第二节"必须轻量"的约束冲突。
> 在定下来之前，**别在文档里声称非交互 shell 能拿到 node**——之前这里就是这么写错的。

**pnpm 留在 11.x，暂不升 12。**

pnpm 12 是 Rust 重写版，2026-08-26 stable。不升的判据不是"才发布几周"，而是**发布节奏本身**：官方还在用 "catch-up" 描述 12.2/12.3 的内容（把 pnpm 11 有而 Rust CLI 没有的功能补回来），到 9 月中旬仍在周更。等 release notes 里不再出现 catch-up、节奏降到月级再说。

> **注意默认值已经变了**：`pnpm self-update` 的默认目标已从 11 改成 12。想留在 11 必须**显式钉住**，项目里用 `package.json` 的 `packageManager` 字段，别裸跑 `self-update`。
>
> 另外 12 有个行为破坏：所有改全局安装的命令在 sudo 下直接报 `ERR_PNPM_SUDO_NOT_SUPPORTED`，以前是静默改 root 家目录。

---

### 步骤 6：Git 与 GitHub CLI

完整流程（含隐私邮箱、凭据助手、代理调优、历史脱敏）见 **[`../../git-github/README.md`](../../git-github/README.md)**。最小必要部分：

```bash
sudo apt install -y gh          # 或用 cli.github.com 官方源装新版
gh auth login                   # 选 GitHub.com -> HTTPS -> Yes -> Login with a web browser
gh auth setup-git

git config --global user.email "<你的ID>+<用户名>@users.noreply.github.com"
git config --global user.name  "<昵称>"
git config --global http.version HTTP/1.1     # 代理环境下规避 GnuTLS 握手失败
```

浏览器唤不起来时，**先看 [`../../git-github/README.md`](../../git-github/README.md) 第二节第 3 小节「故障排查与已知坑」**，里面有 wslu 在 systemd 下的假错、UNC 警告、绝对路径要求等五条。

---

### 步骤 7：中文输入法（可选）

见 [`../gui-ime/wsl-gui-and-ime.md`](../gui-ime/wsl-gui-and-ime.md)。
`~/.shell_common` 第 7 节已经预置了 fcitx5 所需的 `GTK_IM_MODULE` 等环境变量。

### 其它可选组件

| 组件 | 文档 |
| :--- | :--- |
| Windows Terminal 配置 | [`../zsh/`](../zsh/) |
| Docker | [`../../tools/docker/docker.md`](../../tools/docker/docker.md) |
| PowerShell 7 | [`../../windows/powershell/`](../../windows/powershell/) |
| pnpm/npm 磁盘清理 | [`../storage/pnpm-npm-cleanup-20260920.md`](../storage/pnpm-npm-cleanup-20260920.md) |

---

### 维护：WSL 自身走独立更新渠道

**WSL 和 WSL2 内核通过 Microsoft Store / `wsl --update` 分发，不走 Windows Update。**

这条容易被忽略，尤其是在 Windows 侧做了版本锁定的机器上——那套策略对 WSL **完全不起作用**：既没拦住 WSL 更新，也没让你拿到 WSL 的安全修复。2026-09-20 实测印证：

| | 更新前 | 更新后 |
| :--- | :--- | :--- |
| WSL | 2.7.8.0 | 2.7.14.0 |
| 内核 | 6.18.33.1 | 6.18.33.2-2 |
| **Windows 版本号** | 26100.7627 | **26100.7627（没动）** |

```powershell
wsl --update          # Windows 侧执行
wsl --version
```

两个补丁面必须分开看，别混：

| 补丁面 | 渠道 |
| :--- | :--- |
| WSL 本体 + WSL2 内核 | `wsl --update` |
| 发行版用户态（openssl、glibc……） | 发行版自己的 `apt` / `dnf` |

`release/2.7` 是微软的**加固轨**，落后 master 数百个提交，新功能都在 master。所以这条轨上的版本通常是"纯安全、无新功能"，升级风险很低，**但也别指望它修功能性 bug**。

内核版本比较看 `uname -r` 里的 base 号（如 `6.18.33`），**不是后缀**。

Windows 侧把功能更新钉死在某个版本的做法（以及为什么钉了 Windows 也钉不住 WSL），见
[`../../windows/windows-update/`](../../windows/windows-update/)。

---

### 维护：重装的三个层级，从轻到重

出问题时按顺序试，**不要一上来就 `--unregister`**。全部在 Windows 侧 PowerShell 执行。

**层级 1：重启 VM / 升级 WSL 本体。** 大多数"突然连不上网""互操作没反应"到这一步就好了，零数据代价：

```powershell
wsl --shutdown
wsl --update
```

**层级 2：重装单个发行版。** 只动那一个发行版，不碰 Windows 的 WSL 组件：

```powershell
wsl -l -v                    # 先确认名字和版本
wsl --unregister <Name>      # 注意：这会连同它的 ext4.vhdx 一起删掉
wsl --install -d <Name>
```

> `--unregister` **不可撤销**，发行版里的家目录、装的包、改的配置全部消失。执行前先把
> `~` 里要留的东西弄出来——跨发行版传文件见
> [`../../agent/skills/wsl-windows-command/references/cross-distro.md`](../../agent/skills/wsl-windows-command/references/cross-distro.md) 第 2、3 节。
> 另外多发行版机器上它还会顺手摘掉全局 `WSLInterop`，见步骤 1.3。

**层级 3：重装 WSL 的 Windows 功能本身。** 只在前两级都无效、怀疑是 Windows 侧组件损坏时用。需要管理员，**两段之间要重启**：

```powershell
# 关
dism /online /disable-feature /featurename:Microsoft-Windows-Subsystem-Linux /norestart
dism /online /disable-feature /featurename:VirtualMachinePlatform /norestart
# 重启 Windows，然后开
dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

`VirtualMachinePlatform` 这一项容易漏——只关/开 `Microsoft-Windows-Subsystem-Linux` 的话，WSL2 仍然起不来，报错却指向别处。

---

## 四、验证清单

全部执行并核对预期值。任何一项不符，回到对应步骤。

```bash
# 1. PATH 纯净度：应只有 1 条 /mnt/c（VS Code bin）
echo $PATH | tr ':' '\n' | grep '^/mnt/c'

# 2. Windows 函数在【交互】shell 中可用
zsh  -ic 'type reg powershell cmd clip'    # 预期：全部 function
bash -ic 'type -t reg powershell cmd clip' # 预期：全部 function

# 3. Windows 函数在【非交互】shell 中可用（脚本 / AI Agent 场景，关键）
zsh  -c 'type -w reg'                      # 预期：reg: function
#    若显示 not found，说明 ~/.zshenv 没部署或没 source ~/.shell_wslfn
bash -c 'type -t reg'                      # 预期：function
#    注意这条【没有 -i】。bash 非交互既不读 ~/.bashrc 也不读 ~/.profile，
#    靠的是 ~/.shell_wslfn 末尾 export 的 BASH_ENV：父 shell 载入过函数，
#    就把这个钩子交给 bash 子进程。若显示 not found，检查
#    `zsh -c 'echo $BASH_ENV'` 是否为 $HOME/.shell_wslfn。
#    覆盖不到的情形：没有这样一个父 shell，例如从 Windows 直接
#    `wsl.exe -e bash script.sh`——那里只能写绝对路径 /mnt/c/...

# 4. 实际调用 Windows 命令（不必写绝对路径）
reg query "HKCU\\Software\\Microsoft\\Windows\\Shell\\Associations\\UrlAssociations\\https\\UserChoice" /v ProgId
echo "Hello from WSL" | clip.exe           # 到 Windows 里 Ctrl+V 验证

# 5. 浏览器唤起（会真的弹窗）
wslview "https://example.com"

# 6. 两个 shell 的环境变量一致
for s in zsh bash; do $s -ic 'echo "'$s': BROWSER=$BROWSER proxy=$http_proxy PNPM_HOME=$PNPM_HOME"'; done

# 7. 工具链
zsh -ic 'node -v; npm -v; pnpm -v; uv --version; git --version; gh --version'

# 8. 不进 system32：从 Windows 侧目录启动 shell 应自动回 ~
cd /mnt/c/Windows/System32 && zsh -ic 'pwd'   # 预期：/home/<user>

# 9. 无凭据残留
env -i HOME=$HOME TERM=xterm /usr/bin/zsh -ic 'echo ${GITHUB_PERSONAL_ACCESS_TOKEN:-clean}'

# 10. 挂载策略：应恰好 3 条，且全是 rw
grep " /mnt/[cde] " /proc/mounts | sed 's/,aname.*//'
#    若一条都没有：检查 wsl.conf 的 mountFsTab = true，以及三个挂载点目录是否存在
#    探针写 Users/Public，不要写 /mnt/c/Users/$USER：Windows 账户名不等于 $USER，
#    而 drvfs 大小写不敏感会让这个错写法在「两者只差大小写」的机器上照样通过。
touch /mnt/c/Users/Public/.wsl-rw-probe && rm /mnt/c/Users/Public/.wsl-rw-probe && echo "rw OK"

# 11. 互操作 binfmt 守护（多发行版机器）
ls /proc/sys/fs/binfmt_misc/ | grep -q WSLInterop && echo "WSLInterop OK" || echo "MISSING"
systemctl is-active wsl-binfmt-guard.timer     # 预期 active

# 12. /mnt/wsl 跨发行版共享（多发行版机器）
systemctl is-active wsl-mount-guard.timer      # 预期 active
findmnt -no TARGET "/mnt/wsl/$WSL_DISTRO_NAME" # 预期打印该路径
# 挂载必须落在共享 tmpfs 里面：下面两个 id 要一致，不一致说明挂成了被遮蔽的孤儿
awk '$5=="/mnt/wsl"{print "tmpfs id="$1}' /proc/self/mountinfo
awk -v t="/mnt/wsl/$WSL_DISTRO_NAME" '$5==t{print "bind parent="$2}' /proc/self/mountinfo
```

> **第 9 条为什么用 `env -i`**：普通测试会继承当前会话的环境变量，已删除的凭据在重启前仍会显示存在，造成误判。`env -i` 起一个干净环境，才能真正验证文件已清理。

---

## 五、常见问题

**改了 `wsl.conf` 没反应** —— 必须在 Windows 侧 `wsl.exe --shutdown` 后重启 WSL。

**刚才还好好的 Windows 命令，突然报 `exec format error`** —— 你多半刚启动或终止了**另一个 WSL 发行版**。`binfmt_misc` 是内核全局的，那个动作把 `WSLInterop` 给所有发行版一起摘了。跑 `sudo systemctl restart systemd-binfmt`，并按步骤 1.3 装上守护 timer。注意这时 `wsl.exe` 自己也跑不了，**只能在发行版内部修**。

**U 盘插进来后 Windows 弹不出** —— 如果还没应用步骤 1.2 的 fstab 策略，WSL 会自动挂载并持有它，只能 `wsl --shutdown`。应用后 WSL 不再碰固定盘之外的任何盘符。

**`xxx.exe: command not found`** —— `appendWindowsPath=false` 的预期行为。检查 `~/.shell_wslfn` 是否已部署并被 source；该文件没覆盖的命令用绝对路径 `/mnt/c/Windows/System32/xxx.exe`。

**AI Agent 说找不到 `reg` / `powershell`，但你自己敲能用** —— Agent 走非交互 shell，读不到 `~/.zshrc`。确认 `~/.zshenv` 存在且 source 了 `~/.shell_wslfn`。这是 alias 方案彻底行不通、必须用函数的根本原因。

**改了 `~/.shell_common` 但 bash 没生效** —— bash 只在**交互**模式下读 `~/.bashrc`（`~/.bashrc` 开头有非交互早退守卫），脚本中需显式 source。

**`#!/bin/bash` 脚本里 `powershell` / `reg` 报 command not found，但 zsh 里好好的** —— zsh 有 `~/.zshenv` 覆盖每一次调用，bash 没有对等物：`bash -c` 和 `#!/bin/bash` 脚本两个启动文件都不读。出口是 `~/.shell_wslfn` 末尾 export 的 `BASH_ENV`——任何载入过函数的 shell 都把这个钩子传给它的 bash 子进程。查 `zsh -c 'echo $BASH_ENV'`，应为 `$HOME/.shell_wslfn`。
唯一覆盖不到的是**没有这样一个父 shell**的情形（从 Windows 直接 `wsl.exe -e bash script.sh`），那里只能写绝对路径。
注意验收清单第 2 条历史上写的是 `bash -ic`，带 `-i` 正好把这个缺口盖住了——现在第 3 条补了不带 `-i` 的版本。

**换了台机器后 `code` 命令消失，且毫无报错** —— `~/.shell_common` 的 VS Code 探测块**不要**写死 Windows 账户名，也别假设它等于 `$USER`。本机这两者其实并不相等（只差大小写），以前能用纯属侥幸：`/mnt/c` 是 drvfs，继承 NTFS 的大小写不敏感，所以 `Users/$USER` 照样 stat 到实际那个大小写不同的目录。换台名字真的不同的机器，所有探测全落空，而 `Program Files` 那两个兜底只对系统级安装有效（VS Code 默认是 User Installer，装在 AppData 下），于是 `code` 静默不进 PATH——症状会推迟到 `VISUAL="code --wait"` 被用到时才冒出来。
现在的写法是 `$USER` 优先、再 glob `/mnt/c/Users/*/`、最后问一次 Windows 要 `%USERPROFILE%` 并缓存到 `~/.cache/wsl-userprofile`。glob 外面那圈 `[ -d /mnt/c/Users ]` 是必需的：**zsh 在 `for` 列表里遇到无匹配的 glob 会直接中止整个文件**（`NOMATCH` 默认开），而 bash 只是把字面量原样传下去；这个文件两种 shell 都要 source。

**删了凭据但 `echo $VAR` 还有值** —— 当前会话是启动时继承的，重开终端或 `wsl --shutdown` 后消失。用上面第 9 条的 `env -i` 方式验证文件本身。
