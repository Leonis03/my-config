# my-config

*[English](README.md) · 中文（正本）*

一台 WSL2 开发机的配置、技能与踩坑记录。

环境是 **Windows 11 + WSL2 + zsh**，主力工具是 Claude Code 与 Antigravity CLI，网络走本地代理。

> **迁移中**：**Ubuntu 24.04** 是此前的主力发行版，现在日常工作已转到 **Fedora 44**，正在把配置向它对齐。
> 两边并存：`wsl -l -v` 里 Ubuntu 仍是默认（那个 `*`），但实际敲命令的地方是 Fedora。
> 四层 shell 配置的核心三个（`.zshenv` / `.shell_wslfn` / `.shell_common`）两边同哈希，剩下的差异要么是
> 发行版本身决定的（Fedora 的 fcitx5 块、`/etc/bashrc`），要么还在收敛。
> 具体差异与「哪些可避免、哪些不可避免」见 [`wsl/distro-differences.md`](wsl/distro-differences.md)。
>
> 文档里写 Ubuntu 的地方多数仍然成立——差异都在 `distro-differences.md` 里单独记着。

内容分两类：**能直接复制部署的配置文件**，以及**排查过程留下的结论**——后者往往比配置本身更值钱，因为它记录了「为什么是这样」。

> 所有路径、用户名、机器标识、端口与时间戳均已脱敏（`$HOME`、`<your-linux-user>`、
> `<your-windows-user>`、`<vm-1>`、`<proxy-port>`、`<ssh-port>`、`<t-created>`），邮箱写作
> `your-old-email@example.com` 占位。部署前按自己的环境替换。
>
> `wsl/storage/` 里的 `<t-...>` 是**稳定**占位符：同一个 token 在哪出现都指同一时刻，
> 所以取证块之间的时间列比对仍然成立，事件间隔在正文里用时长说明。

---

## 从哪开始

| 你想做什么 | 去哪 |
| :--- | :--- |
| **在新机器上复刻整套环境** | [`wsl/setup/`](wsl/setup/) —— 复刻指南 + 12 个可直接 `cp` 的配置原件 |
| 配 Git 与 GitHub（含隐私邮箱） | [`git-github/`](git-github/) |
| 配 Claude Code | [`agent/claude-code/`](agent/claude-code/) |
| 找一个现成的 skill，或把 skill 同步到本机 | [`agent/skills/`](agent/skills/) —— 18 个；部署走 `tools/sync-skills.sh`，不是 `cp` |
| 查某个具体的坑 | 见下面的「踩坑索引」 |
| 了解这里的写作与发布规矩 | [`conventions.zh.md`](conventions.zh.md) —— ASCII 边界、命名、`tmp/`、发布门禁、双仓同步 |
| 搞懂占位符体系：为什么仓库里没有真用户名，部署却能解析 | [`redaction.zh.md`](redaction.zh.md) —— 三类值的决策树与两条流水线 |

---

## 目录

### [`wsl/`](wsl/) —— WSL2 与 Linux 侧

| 目录 | 内容 |
| :--- | :--- |
| [`setup/`](wsl/setup/) | **环境复刻指南**。`/etc/wsl.conf`、apt 换源、zsh + oh-my-zsh、四层 shell 配置分层、工具链。`files/` 下是可直接部署的原件 |
| [`gui-ime/`](wsl/gui-ime/) | WSLg 图形应用与 fcitx5 中文输入法 |
| [`storage/`](wsl/storage/) | 发行版迁移到非系统盘、VHDX 空间回收、pnpm/npm 磁盘清理。含一次 EACCES 权限故障的完整取证分析 |
| [`zsh/`](wsl/zsh/) | zsh 安装与 System32 自动回家 |

核心是 **`appendWindowsPath=false` + 显式函数桥接**：不注入 Windows 的几百个 PATH 条目，只把真正需要的几个 `.exe` 包成 shell 函数。

### [`windows/`](windows/) —— Windows 侧

[`terminal/`](windows/terminal/)（Windows Terminal 配置）· [`powershell/`](windows/powershell/)（PowerShell 7 profile、PSReadLine、一键关闭所有资源管理器窗口）· [`context-menu/`](windows/context-menu/)（右键菜单项排查与优化）· [`windows-update/`](windows/windows-update/)（把功能更新钉在 24H2，但保留更新可见性）

### [`agent/`](agent/) —— AI 工具链

| 目录 | 内容 |
| :--- | :--- |
| [`claude-code/`](agent/claude-code/) | `settings.json`、全局 `CLAUDE.md`、159 行的状态栏脚本。与本机逐字节一致 |
| [`skills/`](agent/skills/) | 18 个 skill，同时供 `~/.claude/` 与 `~/.gemini/config/`。仓库是脱敏的，部署与核对走 [`tools/sync-skills.sh`](tools/sync-skills.sh) |
| [`antigravity/`](agent/antigravity/) | `~/.gemini/config/AGENTS.md` 原件（强制走 `bx`）、`agy` CLI 使用与图片交接 |
| [`brave-search/`](agent/brave-search/) | `bx` CLI 与 Brave Search MCP 接入 |

### [`git-github/`](git-github/) · [`tools/`](tools/) · `tmp/`

Git 隐私配置与历史脱敏 runbook（含 GitHub 文件大小的四道门槛）；Python 与远程执行的踩坑；
Docker；[`tools/latex/`](tools/latex/)（VS Code LaTeX Workshop 工具链，以及 ChkTeX 为什么在中文环境必须关掉）；
以及两个脚本——[`tools/privacy-gate.sh`](tools/privacy-gate.sh)（发布前的脱敏门禁）和
[`tools/sync-skills.sh`](tools/sync-skills.sh)（skill 的渲染式部署与核对）。

`tmp/` 是**临时工作区**，已 gitignore，一切临时编辑、脚本试跑、覆盖前的备份都在里面做。
三者均见 [`conventions.zh.md`](conventions.zh.md)。

---

## 踩坑索引

这些是排查花了时间、结论又不显然的条目。

| 坑 | 症状 | 在哪 |
| :--- | :--- | :--- |
| **非交互 shell 不展开 alias** | 脚本和 AI agent 报 `command not found`，你自己敲却好好的 | [`wsl/setup/`](wsl/setup/) 第 2 节 |
| **wslu 在 systemd 下误报** | `WSL Interoperability is disabled`，但 `wsl.conf` 明明是对的 | [`git-github/README.md`](git-github/README.md) 二.3 |
| **`filter-repo` 静默毁改动** | 重写历史后未提交的已跟踪修改消失，且无提示 | [`git-github/email-scrub-runbook.md`](git-github/email-scrub-runbook.md) 第 2 节 |
| **`no_proxy` 通配符失效** | 访问本机服务却穿了代理，报 502 空体像"请求失败" | [`tools/python/`](tools/python/) 第 1 节 |
| **f-string 引号规则** | `invalid syntax`，且 3.10 与 3.12 行为不同 | [`tools/python/`](tools/python/) 第 2 节 |
| **`pkill -f` 杀掉自己** | 返回 255，看起来像 SSH 断连 | [`tools/remote-ssh.md`](tools/remote-ssh.md) 第 2 节 |
| **Python 里设线程数太晚** | BLAS 已初始化，48 worker 开 3077 线程，慢 227 倍 | [`tools/remote-ssh.md`](tools/remote-ssh.md) 第 3 节 |
| **盘符路径在 WSL 恒不存在** | `C:/Windows/Fonts/...` 找不到字体，静默出豆腐块且不报错 | [`agent/skills/wsl-cjk-font/`](agent/skills/wsl-cjk-font/) |
| **写死的 Windows 账户名会过期** | 同样是静默豆腐块：`/mnt/c/Users/<旧机器的账户名>/...` 在本机不存在。WSL 里没有 `%USERPROFILE%`，该用 `glob("/mnt/c/Users/*/...")` | [`agent/skills/README.md`](agent/skills/README.md) |
| **drvfs 大小写不敏感，会把写死的账户名藏起来** | 比上一条更阴：本机 Windows 账户名与 `$USER` 只差大小写，字符串相等判断为假，但 `/mnt/c/Users/$USER/...` 照样 stat 成功——于是「用 `$USER` 拼 Windows 家目录」这个错做法在本机**一直是通过的**，换台名字真不同的机器才静默失效 | [`wsl/setup/`](wsl/setup/) 常见问题 |
| **zsh 在 `for` 列表里遇到无匹配 glob 会中止整个文件** | 同一份 `~/.shell_common` 被 bash 和 zsh 共用；bash 把字面量原样传下去，zsh 直接 `no matches found` 退出，后面的配置全不执行 | [`wsl/setup/`](wsl/setup/) 常见问题 |
| **非交互 bash 没有 `.zshenv` 的对等物** | zsh 侧的互操作函数覆盖到了脚本和 agent，bash 侧没有：`bash -c` 和 `#!/bin/bash` 两个启动文件都不读。验收清单历史上写的是 `bash -ic`，带 `-i` 恰好把缺口盖住了。出口是 `BASH_ENV` | [`wsl/setup/`](wsl/setup/) 验证清单第 3 条 |
| **`.gitattributes` 管不到 zip** | 整个文件被报成重写，真改动淹没在假 diff 里 | [`git-github/crlf-and-diffing.md`](git-github/crlf-and-diffing.md) |
| **`/reg:64` 重定向** | 注册表键"明明存在却找不到" | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **`binfmt_misc` 跨发行版全局** | 启停另一个发行版后，Windows 命令突然 `exec format error`，且看不出关联；还没法用互操作自救 | [`wsl/setup/`](wsl/setup/) 步骤 1.3 |
| **`accept4 110` 有两种病因** | 照"换 socket"的通行处方修，所有 socket 同样失败，白烧一小时 | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **`wsl -l -v` 的星号是「默认」不是「当前」** | 把它读成"你在这儿"，`-d <别的发行版>` 就静默回到了你已经在的那个。跨发行版写标记再读回来，测试完美通过——那是你自己的文件。只有 `stat -c %d` 露馅。判据是 `$WSL_DISTRO_NAME` | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) 第 1 节 |
| **跨发行版传文件绕了 Windows** | 能跑，但同一批文件慢 23 倍（0.97 s vs 22.5 s）。`/mnt/wsl` 是 shared tmpfs，bind 到它下面就直通，不必走 `\\wsl.localhost` 的 9p | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) 第 2 节 |
| **`--terminate` 不释放被别人 bind 的盘** | `wsl -l -v` 显示 `Stopped`，另一个发行版照样往它的 ext4 里写，下次启动东西就在那儿；VHDX 也一直挂着，压缩必须 `--shutdown` | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) 第 5 节 |
| **systemd ≥ 256 在 WSL 起不了 user session** | `Failed to spawn executor: Device or resource busy`；Ubuntu 255 没事，Fedora 259 必炸 | [`wsl/distro-differences.md`](wsl/distro-differences.md) |
| **cmd.exe 拒绝 UNC 工作目录** | 静默回退到 `C:\Windows`，路径相关操作全错却不报错 | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **WSL 不走 Windows Update** | Windows 锁了版本，却以为 WSL 也一起锁住了；实际两个渠道互不相干 | [`wsl/setup/`](wsl/setup/) 维护节 |
| **`.wslconfig` 不在仓库里，代理就必然坏** | `host_ip="127.0.0.1"` 只在 `networkingMode=mirrored` 下成立。复刻时漏掉这个 Windows 侧文件，WSL 退回 NAT，`127.0.0.1` 指向它自己，所有代理请求 connection refused——而报错离原因很远，`~/.shell_common` 里没有任何线索 | [`wsl/setup/`](wsl/setup/) 步骤 0.1 |
| **ChkTeX 在中文文档刷屏误报** | `Use "'" (ASCII 39) instead of "´"` 刷满输出，真错误被淹没。它逐字节扫描而非 UTF-8 解码，汉字的后续字节落在 `´`(0xB4) 位上就被当成排版错误。改规则集没用，只能关掉 | [`tools/latex/`](tools/latex/) |
| **`-Source` 给了仍然去连网** | 离线装 Windows 中文字体包，ISO 都挂好了还是失败——`Add-WindowsCapability` 不加 `-LimitAccess` 会先去问 Windows Update | [`tools/latex/`](tools/latex/) · [`agent/skills/wsl-cjk-font/`](agent/skills/wsl-cjk-font/) |
| **pnpm 拦掉 postinstall 但不报错** | `pnpm update -g --latest` 退出码 0、看着装好了，命令却跑不起来——pnpm 10 起默认不执行生命周期脚本。要 `--allow-build=<包名>` 显式放行 | [`wsl/storage/pnpm-npm-cleanup-20260920.md`](wsl/storage/pnpm-npm-cleanup-20260920.md) 3.2 |
| **脱敏占位符借用了 `$HOME`** | 同一个记号既表示"待替换的家目录"，又表示真正的 shell 变量；一渲染就把 `set-deepln.sh` 里的 `$HOME` 硬编码成本机路径，脚本到了租来的 GPU 机上全错。判据应该是"会不会被 shell 展开"，不是文件类型 | [`agent/skills/README.md`](agent/skills/README.md) |
| **jq 路径写错静默出 0 行** | 对 `bx news` 用 `.web.results[]`，exit 0 无报错，看起来像"这话题没结果" | [`agent/brave-search/bx-cli.md`](agent/brave-search/bx-cli.md) 第 6 节 |
| **搜索前置 skill 成了固定税** | CLAUDE.md 每会话常驻、skill 正文按需加载，把 2.2k 的 skill 设成 `bx` 前置，成本结构正好反了 | [`agent/claude-code/README.md`](agent/claude-code/README.md) |
| **脱敏正则反复漏网** | 同一个值换种渲染方式（大小写、列对齐、另一条命令的输出格式、换语言的标签）就逃过检查，5 轮都栽在这 | [`tools/privacy-gate.sh`](tools/privacy-gate.sh) 头部注释 |
| **Wayland 下输入法绑不上** | Electron 应用跑得好好的就是打不出中文，flag 怎么调都没用。Weston 把 `input_method` 留给自己的 IME 客户端，WSLg 又不跑它；更坑的是 fcitx5 撞上 error 71 会**整个进程退出**，连 X11 侧输入法一起没 | [`wsl/gui-ime/`](wsl/gui-ime/) 第 1、9 节 |
| **`wmctrl` 在 WSLg 全废** | 窗口摆放脚本静默空转、什么也没发生。Weston WM 不导出 `_NET_CLIENT_LIST`，`wmctrl -l` 恒失败，而脚本恰好用它找窗口 | [`wsl/gui-ime/`](wsl/gui-ime/) 第 8 节 |
| **机器换了、文档没换** | 一份「部署总结」里的显示参数、文件角色、修复方案全对不上本机。用首次运行留下的痕迹（`Crashpad/client_id`）与文档落款比时间，就能判定它根本不是在这台机器上写的 | [`wsl/gui-ime/`](wsl/gui-ime/) 第 5、8 节 |
| **PRoot 下 xrdb 无超时挂死整个桌面** | 荣耀平板 Linux 实验室切 Debian 永久卡在「加载中」，`xrdb -merge` 系统调用死锁阻断 `StartFinished` 握手信号；修改 `start` 会被 `AssetsPatcher` 校验覆写，需用子程序 wrapper 拦截规避 | [`agent/skills/honor-linuxlab/`](agent/skills/honor-linuxlab/) |
| **ARM64 换 Ubuntu 镜像源必须用 ubuntu-ports** | 平板换清华源后 `apt update` 报 404 找不到 `binary-arm64/Packages`，因为非 x86 架构在独立路径下 | [`agent/skills/honor-linuxlab/`](agent/skills/honor-linuxlab/) |
| **`execve` 与 `/proc/self/exe` 解耦** | 命令执行报 `readlink /proc/self/exe: no such file`，误以为内核无法派生进程。Linux `execve(2)` 本身不依赖 `/proc`，是 Go/CLI 运行器做自省与路径解析时受阻，挂载 `/proc` 仅是满足运行时自省而非提权 | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **`unshare -m` 隔绝了父子会话挂载** | 宿主更新了 chroot 挂载且 `--check` 通过，已运行的 agent 依然报 `open /dev/ptmx: no such device`。`unshare -m` 创建了独立 Mount Namespace，旧终端里的 `bash` 未退出导致重启的 agent 仍困在旧命名空间 | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **Android Termux 报 `required file not found`** | 执行官方安装的 CLI 工具报文件未找到，但 `ls` 明明在；`readelf -l` 发现其 `PT_INTERP` 请求 `/lib/ld-linux-aarch64.so.1`，而 Android 原生使用 Bionic libc（`/system/bin/linker64`），内核找不到 glibc 解释器返回 ENOENT，必须用 chroot/glibc 容器 | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **热插拔移动硬盘在 chroot 隔离中失明** | 进入 Debian 容器后再插入移动硬盘，Android 正常识别但容器内 `/android/mnt/media_rw` 为空。`unshare -m` 与 `rprivate` 阻断了挂载传播，需通过 `nsenter -t 1 -m` 穿透宿主命名空间动态桥接挂载 | [`agent/skills/termux-debian-external-drive/`](agent/skills/termux-debian-external-drive/) |
| **NTFS 权限伪造阻断 SSH 密钥认证** | 移动硬盘上私钥执行 `chmod 600` 虽返回 0 但底层 FUSE 驱动固化为 `770`，触发 OpenSSH 门禁拒连；必须用 `tar` 归档保留 POSIX 权限并在本地 Linux 文件系统解压 | [`agent/skills/termux-debian-external-drive/`](agent/skills/termux-debian-external-drive/) |

---

## 许可证

版权所有 © 2026 Leo `<28289630+Leonis03@users.noreply.github.com>`

**代码与配置走 [MIT](LICENSE)，文档走 [CC BY 4.0](LICENSE-DOCS)。** 两者都允许商用、允许再分发、都要求注明来源。

| 范围 | 许可证 | 覆盖什么 |
| :--- | :--- | :--- |
| 代码与配置 | [MIT](LICENSE) | 所有**非** `.md` 的文件——`tools/` 与 `agent/skills/*/scripts/` 下的 `.sh` / `.py`、`windows/` 下的 `.ps1`、`wsl/setup/files/` 下的配置原件、`.gitignore` |
| 文档 | [CC BY 4.0](LICENSE-DOCS) | 所有 `.md` 文件——两个 README、各目录的说明、skill 正文、踩坑记录与取证分析 |

拆开是因为 **Creative Commons 自己不建议把 CC 用于软件**，FSF 亦然（CC BY 4.0 虽是自由许可证、也兼容 GPL，但「should not be used on software」），而 OSI 从未批准过任何 CC 许可证。CC BY 4.0 §2(b)(2) 明示**不授予专利权**，§6(a) 规定违约**自动终止**（§6(b) 给 30 天补救），§2(a)(5)(B) 还禁止施加技术保护措施——这些条款对散文无害，对会被反复复制的脚本是真麻烦。

### 第三方内容

下列部分**不属于**上面两个许可证，版权归各自作者：

- `windows/powershell/SamplePSReadLineProfile_GitHub.ps1` —— [PowerShell/PSReadLine](https://github.com/PowerShell/PSReadLine) 官方示例的逐字副本，694 行，Copyright (c) 2013 Jason Shirk，**BSD-2-Clause**。完整声明已写在该文件头部。
- `wsl/setup/files/bashrc` 保留了 Debian 出厂 `.bashrc` 的若干片段（`shopt -s checkwinsize`、`lesspipe`、`dircolors`、`alias ll=` 等）。
- `wsl/setup/files/` 下几个文件含安装器生成的块：oh-my-zsh 相关行、Antigravity CLI 的 PATH 块。

这些都是被广泛复制的模板片段，此处如实标注，不主张对它们的版权。
