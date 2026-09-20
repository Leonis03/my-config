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
| 找一个现成的 skill，或把 skill 同步到本机 | [`agent/skills/`](agent/skills/) —— 14 个；部署走 `tools/sync-skills.sh`，不是 `cp` |
| 查某个具体的坑 | 见下面的「踩坑索引」 |

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
| [`skills/`](agent/skills/) | 14 个 skill，同时供 `~/.claude/` 与 `~/.gemini/config/`。仓库是脱敏的，部署与核对走 [`tools/sync-skills.sh`](tools/sync-skills.sh) |
| [`antigravity/`](agent/antigravity/) | `~/.gemini/config/AGENTS.md` 原件（强制走 `bx`）、`agy` CLI 使用与图片交接 |
| [`brave-search/`](agent/brave-search/) | `bx` CLI 与 Brave Search MCP 接入 |

### [`git-github/`](git-github/) · [`tools/`](tools/) · `tmp/`

Git 隐私配置与历史脱敏 runbook（含 GitHub 文件大小的四道门槛）；Python 与远程执行的踩坑；
Docker；[`tools/latex/`](tools/latex/)（VS Code LaTeX Workshop 工具链，以及 ChkTeX 为什么在中文环境必须关掉）；
以及两个脚本——[`tools/privacy-gate.sh`](tools/privacy-gate.sh)（发布前的脱敏门禁）和
[`tools/sync-skills.sh`](tools/sync-skills.sh)（skill 的渲染式部署与核对）。

`tmp/` 是**临时工作区**，已 gitignore，一切临时编辑、脚本试跑、覆盖前的备份都在里面做。
三者均见下方「约定」。

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

---

## 脱敏与跨设备：一个值该怎么写

仓库要同时满足两件看起来矛盾的事：**被跟踪的字节里没有真实用户名**，而**部署到任何一台机器上都能解析成真值**。做法是按「它在目标机器上怎么变成真值」把值分成三类——判据是**会不会被 shell 展开**，不是它出现在什么文件里。

```
            要往被跟踪的文件里写一个「名字形状」的值
                              |
                              v
                 +------------------------+
                 | 这个位置会被 shell 展开? |
                 +-----------+------------+
                   会        |        不会
          +------------------+        +------------------+
          v                                              v
 +------------------+                      +--------------------------+
 | (1) 运行时变量    |                      | 能在目标机器上「探测」出来? |
 |                  |                      +------------+-------------+
 | 原样发布:         |                          能       |       不能
 |   $HOME  $USER   |              +--------------------+        |
 |                  |              v                             v
 | 谁展开: 目标机的   |   +-------------------------+  +--------------------+
 | shell            |   | (2) 运行时探测           |  | (3) 占位符          |
 |                  |   |                         |  |                    |
 | 只对 Linux 侧成立 |   | 原样发布探测代码:        |  | 发布: <your-home>   |
 | Windows 账户名    |   |  glob /mnt/c/Users/*/   |  |      <your-windows- |
 | 不等于 $USER      |   |  %USERPROFILE%+wslpath  |  |       user>         |
 |                  |   |  ~/.cache 兜底(带自愈)   |  |                    |
 |                  |   |                         |  | 谁替换: 部署脚本     |
 |                  |   | 谁解析: 目标机自己       |  | sync-skills.sh      |
 |                  |   | 跨机器自动正确           |  | 查 .sync-map        |
 +------------------+   +-------------------------+  +--------------------+
                                                              |
                                    用在 shell 展不开的地方 ---+
                                    (JSON、Python 字符串字面量)
```

两个方向各自的流水线：

```
【发布方向】 工作副本 --> 公开仓库
       |
       |  被跟踪的字节里只有 (1)(2)(3) 三种形态，没有真名
       v
  privacy-gate.sh        账户名不写在脚本里(写进去脚本自己就是泄露源)
  读 tools/.privacy-names   跳过 tmp/   只覆盖已知形态: 跑通 != 安全
       | pass
       v
  git archive HEAD | tar -x -C ../my-config-public
       +-- 不用 cp -r: 它会把 gitignore 挡住的私有文件一并拷走

【部署方向】 仓库 --> 本机(Fedora / Ubuntu / 租来的 GPU 机)
       |
  +----+----+
  v         v
(1)(2)     (3)
cp 即可    sync-skills.sh deploy 查 tools/.sync-map 渲染成真值
到机器上     核对时比对【渲染后】的字节
自己解析     所以「哈希相同」= 仓库 ≡ 部署位，模脱敏
```

| 类 | 实例 | 为什么归这类 |
| :--- | :--- | :--- |
| (1) 运行时变量 | `$HOME`；`shell_common` 里 `"/mnt/c/Users/$USER"` 这一步首探 | shell 会展开，Linux 侧永远正确 |
| (2) 运行时探测 | `cjk_font.py` 的 `glob("/mnt/c/Users/*/...")`、`WT_SETTINGS` 与 `wt.exe` 别名的 glob、fontconfig 生成、`%USERPROFILE%`+`wslpath`、`~/.cache/wsl-userprofile` 兜底 | 没有任何 shell 变量能给出 Windows 账户名 |
| (3) 占位符 | JSON 里的 `<your-home>`（全仓库只剩两行）、`.sync-map` 覆盖的 `<your-windows-user>` | shell 在那些位置不展开 |

支点是两个 gitignore 的运行时文件：`tools/.privacy-names`（门禁扫描用的真名）与 `tools/.sync-map`（占位符 → 真值映射）。理由是同一句话：**真值留在运行时文件里，脚本本身才能被发布**。

已知薄弱处三条，都在「踩坑索引」里有对应条目：分类会选错且错得静默（`$USER` 撞上 drvfs 大小写不敏感）；兜底缓存缺失效检测（已改成两遍自愈）；门禁只覆盖已知形态。

---

## 约定

- **这些地方只用纯 ASCII**：目录名与文件名、系统与工具的配置文件（**含其中的注释**，注释写英文）、
  每个 skill 的 YAML frontmatter（尤其 `description`，它每个会话都加载并参与触发匹配）。
  正文文档（README、`references/*.md`、skill 的 frontmatter 以下部分）用中文。
  非 ASCII 跑到上面那几处，故障会**静默且远离原因**——跨 WSL/Windows 边界、打包、shell 与 harness 解析。
- **Markdown 文件名一律小写 kebab-case**：`wsl-gui-and-ime.md`，不用大写、下划线或空格。
  取证记录与时点快照在名字末尾加 `-YYYYMMDD`（`etc-diff-analysis-20260330.md`、
  `pnpm-npm-cleanup-20260920.md`），流程型与常青文档不加。
  唯一的例外是**协议性文件名**：`README.md`、`README.zh.md`、`SKILL.md`、`SKILL.zh.md`、
  `CLAUDE.md`、`TROUBLESHOOTING.md`——它们被工具或 harness 按字面查找，改了就失效。
- **根 README 双语**：`README.md` 是英文（GitHub 默认渲染的那一份），`README.zh.md` 是中文正本。
  改动先落在中文版，再同步英文版——踩坑索引的措辞是排查结论的浓缩，先用母语写准再翻译。
  子目录的 README 仍只有中文。
- **Python 走 `uv`，固定 3.12**。系统 `/usr/bin/python3` 保留给 Ubuntu 的 apt 包，不动它。
- **装 skill 用 `cp`，不用 `ln -s`**。这棵树会在机器、文件系统和操作系统之间搬动，符号链接活不下来。
- **同步 skill 用 `bash tools/sync-skills.sh`，也不要裸 `cp`**。仓库里写的是 `<your-home>`、
  `CourseName` 这类占位符，脚本在写入 `~/.claude/skills/` 与 `~/.gemini/config/skills/`
  时展开成真值，核对时比对**渲染后**的字节——所以"哈希相同"的含义是「仓库 ≡ 部署位，模脱敏」。
  不带参数跑是只读核对。家目录的写法看**会不会被 shell 展开**：会展开就写 `$HOME`（原样发布的
  运行时变量，不是占位符），展不开才写 `<your-home>`——全仓库只剩 JSON 里的两行，
  详见 [`agent/skills/README.md`](agent/skills/README.md)。
- **临时的事情一律在 `tmp/` 里做**：要改之前先备份的副本、脚本的中间产物、想跑一下看看的片段、
  原始命令输出——都放这儿，不要散在仓库根目录，也不要丢进系统 `/tmp`（重启即失，第二天想复看时已经没了）。
  这个目录已 gitignore，`git archive` 导不出去，`privacy-gate.sh` 也**跳过**它，
  所以里面可以放带真实路径和账户名的东西，不会把门禁搞成天天红。
  `tmp/.gitkeep` 是被跟踪的，新 clone 下来目录就在。
- **发布前跑 `bash tools/privacy-gate.sh`**。它只覆盖已知形态，跑通不等于安全——`wsl/storage/` 是原始取证输出，必须人工读。
  账户名**不写在脚本里**（写进去，这个脚本自己就成了泄露源），运行时从 `tools/.privacy-names`（已 gitignore）读取。
- **导出公开副本用 `git archive`，不要 `cp -r`**。`cp -r` 会把靠 gitignore 挡住的本地私有文件一并复制进公开目录。
  本仓库是**私有主仓 + 公开快照**的双仓结构，公开仓自带 `.git`，所以同步流程固定为四步：

  ```bash
  cd ~/dev/my-config                                   # 公开仓
  find . -mindepth 1 -maxdepth 1 -not -name '.git' -exec rm -rf {} +
  ( cd ../my-config-private && git archive HEAD ) | tar -x -C .
  git add -A && git commit && git push
  ```

  **第二步「清空」不能省。** 不清空的话，私有仓里删掉的文件在公开仓会残留——`tar -x` 只覆盖不删除。
  而清空必须 `-not -name '.git'`，否则连仓库本身一起没了。
  **第三步用 `git archive` 而不是 `cp -r`**，这样 `tools/.privacy-names`、`tools/.sync-map`、`tmp/` 天然进不去。
  推送前核一遍：`find . -type f -not -path './.git/*' | git check-ignore --stdin`，应无输出。

  公开仓走**正常历史**，普通 `commit` + `push`，不要 `--amend` 强推——它上线后任何人 clone 过就会被打乱。
  （历史上有两次 amend：一次补许可证、一次改提交消息格式，都在无人 clone 的窗口内。）
- **凭据不进版本库**。需要环境变量形式的 token 时放 `~/.shell_secrets`（`chmod 600`），由 `~/.shell_common` 末尾自动加载。

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
- `wsl/setup/files/` 下几个文件含安装器生成的块：`>>> conda initialize <<<`（Anaconda）、oh-my-zsh 相关行、Antigravity CLI 的 PATH 块。

这些都是被广泛复制的模板片段，此处如实标注，不主张对它们的版权。
