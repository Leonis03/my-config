# GitHub 隐私保护与 GitHub CLI (gh) 配置与运维指南

本指南整合了 GitHub 邮箱隐私保护、WSL 环境下的浏览器唤起、GitHub CLI (`gh`) 登录与凭证管理、Git 代理网络调优、历史提交真实邮箱清洗脱敏以及仓库私有化管理的全套可复现方案。

---

## 目录

1. [本地 Git 隐私提交身份配置](#一本地-git-隐私提交身份配置)
2. [WSL 环境浏览器联动配置 (用于 CLI 登录)](#二wsl-环境浏览器联动配置-用于-cli-登录)
3. [GitHub CLI (gh) 登录与 Git 凭证助手集成](#三github-cli-gh-登录与-git-凭证助手集成)
4. [代理环境下的 Git 网络传输调优](#四代理环境下的-git-网络传输调优)
5. [清洗历史 Commit 中的真实邮箱 (git-filter-repo)](#五清洗历史-commit-中的真实邮箱-git-filter-repo)
6. [个人仓库批量转为 Private 及验证](#六个人仓库批量转为-private-及验证)
7. [日常检查与验证命令速查](#七日常检查与验证命令速查)
8. [文件大小限制](#八文件大小限制)

---

## 一、本地 Git 隐私提交身份配置

### 1. 原理
GitHub 提供了 **"Keep my email addresses private"**（保持邮箱地址私有）功能。开启后：
* GitHub 在 Web 端操作（如网页创建、合并、编辑）时会自动使用形如 `ID+Username@users.noreply.github.com` 的匿名邮箱。
* 在本地命令行执行 `git commit` 时，必须显式将 `user.email` 设置为该匿名地址，否则真实的个人邮箱会被永久固化在 commit 元数据中。
* 提交者的名字（`user.name`）主要用于显示，不影响 GitHub 账号的关联统计，可使用网名或昵称。

### 2. 可复现配置命令

```bash
# 设置全局 Git 提交邮箱为 GitHub noreply 隐私邮箱
git config --global user.email "28289630+Leonis03@users.noreply.github.com"

# 设置全局 Git 提交用户名（可使用昵称）
git config --global user.name "Leo"

# 验证配置
git config --global user.email
git config --global user.name
```

---

## 二、WSL 环境浏览器联动配置 (用于 CLI 登录)

### 1. 背景问题
在 WSL 环境中，若 `/etc/wsl.conf` 配置了 `appendWindowsPath = false`（防止 Windows 环境变量污染 Linux PATH），Linux 终端无法直接通过 `cmd.exe` 或默认 `wslview` 唤起 Windows 浏览器完成网页授权登录（如 `gh auth login`）。

### 2. 解决方案与命令
创建 `/usr/local/bin/wslview` 独立脚本，使用 Windows 绝对路径调用 `rundll32.exe`，并将其配置为全局 `BROWSER`。

```bash
# 1. 创建独立唤起脚本
sudo tee /usr/local/bin/wslview <<'EOF' >/dev/null
#!/bin/sh
# 调用 Windows 默认浏览器打开 URL
if [ $# -eq 0 ]; then
    echo "Usage: wslview <url>" >&2
    exit 1
fi
cd /mnt/c/Windows/Temp 2>/dev/null || cd /mnt/c
exec /mnt/c/Windows/System32/rundll32.exe url.dll,FileProtocolHandler "$1"
EOF

# 2. 赋予可执行权限
sudo chmod +x /usr/local/bin/wslview

# 3. 设置默认浏览器环境变量（写入 ~/.bashrc 并立即生效）
grep -q 'BROWSER=wslview' ~/.bashrc 2>/dev/null || echo 'export BROWSER=wslview' >> ~/.bashrc
export BROWSER=wslview

# 4. 测试唤起 Windows 浏览器
wslview "https://github.com"
```

### 3. 故障排查与已知坑

#### (a) `wslview` 报 "WSL Interoperability is disabled" —— 多半是假错

新版 WSL 把 binfmt_misc 的互操作处理器从 `WSLInterop` 改名为 `WSLInterop-late`，而 wslu 仍硬编码检查旧名，于是在 `systemd=true` 的发行版上误报：

```
grep: /proc/sys/fs/binfmt_misc/WSLInterop: No such file or directory
WSL Interopability is disabled. Please enable it before using WSL.
```

> [!IMPORTANT]
> 这条报错极具误导性 —— 它会把人引去改 `/etc/wsl.conf` 里**本来就正确**的 `enabled=true`。真正该查的是 binfmt_misc 里的注册名。
> 在 Ubuntu 24.04 干净装 wslu 的场景下，`wslview` 可能每次执行都崩溃，并级联报出 `/mnt/c/Windows/System32/reg.exe: No such file or directory`。

诊断：

```bash
ls /proc/sys/fs/binfmt_misc/
# 含 WSLInterop        -> 不受影响
# 只有 WSLInterop-late -> 命中该 bug
```

持久化修复（systemd 原生，重启后仍生效）：

```bash
echo ':WSLInterop:M::MZ::/init:P' | sudo tee /etc/binfmt.d/99-WSLInterop.conf
sudo systemctl restart systemd-binfmt
```

直接写 `/proc/sys/fs/binfmt_misc/register` 也能修，但那是虚拟文件系统，WSL 重启即失效。

追踪：[microsoft/WSL#13449](https://github.com/microsoft/WSL/issues/13449)、[#13390](https://github.com/microsoft/WSL/issues/13390)、[Ubuntu wslu #2125223](https://bugs.launchpad.net/ubuntu/+source/wslu/+bug/2125223)。

> **台式机实测状态（2026-09-19，WSL2 / Ubuntu noble / systemd=true / wslu 3.2.3）**：注册名为旧名 `WSLInterop`，**不受影响**，`wslview`、`rundll32` 方案、`xdg-open` 三种方式均实测可唤起 Chrome。

#### (b) 用 alias 包装 Windows 命令对 `gh auth login` 无效

`alias open='explorer.exe'` 这类写法**只在你手敲命令时生效**。`gh` 内部起子 shell 调用浏览器时别名不传递，授权页面依然打不开。必须走 `BROWSER` 环境变量或 PATH 上的可执行脚本 —— 这正是本节采用 `/usr/local/bin/wslview` 脚本 + `BROWSER` 而非 alias 的原因。

#### (c) `appendWindowsPath=false` 下所有 .exe 都必须用绝对路径

Windows PATH 不再注入，`reg.exe`、`rundll32.exe`、`powershell.exe` 直接敲都会 `command not found`。只有由 Linux 包提供的包装器（如 wslu 的 `/usr/bin/wslview`）不受影响。

```bash
reg.exe query ...                          # ✗ command not found
/mnt/c/Windows/System32/reg.exe query ...  # ✓
```

#### (d) 从 Linux 路径直接执行 .exe 会触发 UNC 警告

```
CMD.EXE was started with the above path as the current directory.
UNC paths are not supported. Defaulting to Windows directory.
```

WSL 的 Linux 路径在 Windows 侧是 `\\wsl.localhost\...` UNC 路径。规避办法就是上文脚本里那句 `cd /mnt/c/Windows/Temp` —— 先切到 Windows 侧路径再 exec。

#### (e) `BROWSER` 应加存在性守卫

裸写 `export BROWSER=wslview`，在 wslu 未装或被卸载后会让 `BROWSER` 指向不存在的命令。建议：

```bash
if command -v wslview >/dev/null 2>&1; then
  export BROWSER=wslview
fi
```

---

## 三、GitHub CLI (gh) 登录与 Git 凭证助手集成

### 1. 安装与登录
使用 `gh` 进行命令行授权，免去手动生成与维护 GitHub Personal Access Token (PAT) 的繁琐步骤。

```bash
# 1. 确保已安装 gh
sudo apt update && sudo apt install -y gh

# 2. 发起登录授权
gh auth login
```
**交互选项说明**：
* *What account do you want to log into?* → **`GitHub.com`**
* *What is your preferred protocol for Git operations on this host?* → **`HTTPS`**
* *Authenticate Git with your GitHub credentials?* → **`Yes`**
* *How would you like to authenticate GitHub CLI?* → **`Login with a web browser`**
* 按回车复制一次性验证码，浏览器自动打开，粘贴验证码完成授权。

### 2. 配置 Git Credential Helper
让本地 `git clone` / `git push` 自动借用 `gh` 的 OAuth 令牌进行免密认证：

```bash
gh auth setup-git

# 验证 helper 配置是否成功
git config --global --get credential.https://github.com.helper
# 预期输出: !/usr/bin/gh auth git-credential
```

---

## 四、代理环境下的 Git 网络传输调优

### 1. 问题背景
在本地开启代理（如 Clash 监听 `127.0.0.1:<proxy-port>`）的环境下，Git 默认基于 GnuTLS/HTTP2 协议访问 GitHub 时，极易出现 `GnuTLS recv error (-110): The TLS connection was non-properly terminated` 或握手挂起。

### 2. 优化命令
全局将 Git HTTP 协议版本强制指定为兼容性最佳的 `HTTP/1.1`：

```bash
# 全局设置 HTTP/1.1 协议
git config --global http.version HTTP/1.1

# 检查当前配置
git config --global --get http.version
```

---

## 五、清洗历史 Commit 中的真实邮箱 (git-filter-repo)

> [!IMPORTANT]
> **要实际执行清洗，请用 [`email-scrub-runbook.md`](email-scrub-runbook.md)，不要直接照抄本节。**
> 本节讲的是原理与命令形态；runbook 里有本机的待清仓库清单、前置门禁，以及一个本节没提、会**静默销毁未提交修改**的坑（已实测确认）。

> [!WARNING]
> 重写 Git 历史会修改所有受影响 Commit 的 SHA-1 哈希值。强制推送（Force Push）会覆盖远端历史，操作前请确认仓库无他人协作。

### 1. 安装 git-filter-repo
`git-filter-repo` 是官方推荐取代过时 `git filter-branch` 的高效重写工具：

```bash
sudo apt update && sudo apt install -y git-filter-repo
git filter-repo --version
```

### 2. 批量重写与推送流程

```bash
# 1. 创建干净的临时重写工作区
mkdir -p /tmp/gitrewrite && cd /tmp/gitrewrite

# 2. 编写 mailmap 文件（格式：新昵称 <新隐私邮箱> <旧真实邮箱>，可同时统一名字与邮箱）
cat > mailmap <<'EOF'
Leo <28289630+Leonis03@users.noreply.github.com> <your-old-email@example.com>
EOF

# 3. 指定需要重写历史的远端仓库列表（以空格隔开）
TARGET_REPOS=("repo-a" "repo-b" "repo-d")

# 4. 执行克隆、脱敏重写并强制镜像推送
for repo in "${TARGET_REPOS[@]}"; do
  echo "==================== 处理仓库: $repo ===================="
  # 以 bare 模式克隆所有分支与标签
  git clone --bare "https://github.com/Leonis03/$repo.git" "$repo.git"
  cd "$repo.git"
  
  # 执行历史重写
  git filter-repo --mailmap /tmp/gitrewrite/mailmap --force
  
  # 打印重写后所有提交身份，确认真实邮箱已被清除
  echo "--- 重写后身份列表 ---"
  git log --all --format='author: %an <%ae> | committer: %cn <%ce>' | sort -u
  
  # 重新绑定远端地址并全量覆盖推送
  git remote add origin "https://github.com/Leonis03/$repo.git"
  git push --force --mirror origin
  
  cd /tmp/gitrewrite
done

# 5. 清理临时文件夹
rm -rf /tmp/gitrewrite
```

### 3. 本地独立仓库单步清洗（尚未绑定远端）

若仓库仅在本地未推送到 GitHub（例如新建的 `model/b`），可直接在仓库根目录就地清洗：

```bash
cd /path/to/local/repo

# 1. 创建备份（安全起见）
cp -r .git .git.bak

# 2. 准备 mailmap 映射
cat > /tmp/mailmap <<'EOF'
Leo <28289630+Leonis03@users.noreply.github.com> <your-old-email@example.com>
EOF

# 3. 就地重写并验证
git filter-repo --mailmap /tmp/mailmap --force
rm -f /tmp/mailmap

# 4. 确认所有提交作者已脱敏
git log --all --format='author: %an <%ae> | committer: %cn <%ce>' | sort -u
```


---

## 六、个人仓库批量转为 Private 及验证

### 1. 批量设置私有可见性

```bash
REPOS=("repo-a" "repo-b" "repo-c" "repo-d")

for repo in "${REPOS[@]}"; do
  echo "Setting Leonis03/$repo to private..."
  gh repo edit "Leonis03/$repo" --visibility private
done
```

### 2. 验证仓库私有状态与远端 Commit 邮箱

```bash
# 验证仓库 visibility 与 private 状态
for repo in "${REPOS[@]}"; do
  gh api "repos/Leonis03/$repo" --jq '"\(.name): visibility=\(.visibility), private=\(.private)"'
done

# 抽样检查远端实际 Commit 记录的作者邮箱是否均为隐私邮箱
for repo in "${REPOS[@]}"; do
  echo "=== $repo 远端 Commit 邮箱 ==="
  gh api "repos/Leonis03/$repo/commits?per_page=20" --jq '.[] | "\(.commit.author.name) <\(.commit.author.email)>"' 2>/dev/null | sort -u
done
```

---

## 七、日常检查与验证命令速查

| 检查项 | 命令 | 预期安全值 / 输出 |
| :--- | :--- | :--- |
| **全局 Git 提交邮箱** | `git config --global user.email` | `28289630+Leonis03@users.noreply.github.com` |
| **全局 Git 提交用户名** | `git config --global user.name` | `Leo` |
| **当前仓库生效身份** | `git config user.email` | （同上，无仓库级别泄漏覆盖） |
| **Git 凭证助手状态** | `git config --global credential.https://github.com.helper` | `!/usr/bin/gh auth git-credential` |
| **Git 网络传输协议** | `git config --global http.version` | `HTTP/1.1` |
| **gh 登录账号状态** | `gh auth status` | `Logged in to github.com account Leonis03` |
| **最近一次 Commit 身份** | `git log -1 --format='%an <%ae>'` | 提交者与提交邮箱均为隐私设置 |

---

## 八、文件大小限制

四道门槛，单位是 **MiB 不是 MB**（GitHub 官方文档用的就是 MiB）：

| 大小 | 会发生什么 |
| :--- | :--- |
| ≤ 25 MiB | 网页端 `Add file → Upload files` 可传 |
| 25 – 50 MiB | 网页端**不让传**，但 `git push` 正常 |
| 50 – 100 MiB | 能推，但 Git 会给**警告**。历史里留着会拖慢每一次 clone |
| > 100 MiB | **直接拒绝**。必须改用 Git LFS，或换分发方式 |

**Release 附件是另一套规则**：仓库总量不限，但**单个文件必须 < 2 GiB**。发大文件（模型权重、安装包、数据集）走 Releases 比塞进 Git 历史合适——历史里的大文件删不掉，只能重写历史。

被 100 MiB 挡住时的选择顺序：

1. **这个文件该不该进版本库**——构建产物、缓存、下载的依赖都不该进，加进 `.gitignore` 即可
2. **能不能走 Releases 附件**——发布物、二进制分发首选
3. **确实需要版本化的大文件**才上 Git LFS

> 已经推上去再想删，靠 `git rm` 没用——文件还在历史里。得 `git filter-repo` 重写，注意它
> 会**静默丢弃未提交的已跟踪修改**，见
> [`email-scrub-runbook.md`](email-scrub-runbook.md) 第 2 节。
