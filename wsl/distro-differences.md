# WSL 发行版差异

同一台宿主机、同一个 WSL 内核下，不同发行版的行为差异。本文只收**实测过**的结论。

---

## 一、systemd ≥ 256 在 WSL 上起不了 user session

### 症状

发行版启动时报：

```
wsl: Failed to start the systemd user session for '<user>'. See journalctl for more details.
```

### 先别查错地方

`journalctl --user -b` **查不出这个问题**，必然返回 `No journal files were found`——user manager 没起来就不会有 user journal。要查系统 journal 里的那个 unit：

```bash
sudo journalctl -u user@1000.service -b
```

真实错误是：

```
user@1000.service: Failed to destroy cgroup /user.slice/user-1000.slice/user@1000.service, ignoring: Device or resource busy
user@1000.service: Failed to spawn executor: Device or resource busy
user@1000.service: Failed with result 'resources'.
```

**两处 EBUSY，第一处才是因**：cgroup 销毁不掉，说明它非空。

### 受控对比（2026-09-19 实测）

同一台机器、**同一个 WSL 内核 6.18.33.1**，只差 systemd 版本：

| 发行版 | systemd | `user@1000.service` |
| :--- | :--- | :--- |
| Ubuntu 24.04 | 255 | **active (running)** |
| Fedora 44 | 259 | **failed (resources)** |

所以这**不是**"WSL 对某个发行版适配不好"。

### 根因

WSL 的 `mini_init` / `/init` / `plan9` 等进程**待在根 cgroup 里**。本机实测根 cgroup 有 19 个条目，全部显示为 PID 0（WSL 的 PID 命名空间把宿主侧进程遮掉了，`/proc/0` 并不存在）：

```bash
for p in $(cat /sys/fs/cgroup/cgroup.procs); do
  echo "PID $p -> $(cat /proc/$p/comm 2>/dev/null || echo '(幽灵)')"
done
```

而 cgroup v2 有条铁律：**内部节点不能有进程**。根节点被占用，控制器委派就失败。systemd 256 起改用 `clone3(CLONE_INTO_CGROUP)` 把 executor 直接生到目标 cgroup 里，这个系统调用在此种状态下返回 EBUSY。systemd 255 走的是老的 fork+exec 再挂载路径，不碰这个机制，因此躲过一劫。

**结论：WSL 内核的 cgroup 布局缺陷 × systemd 新 spawn 机制的交互。** systemd 256 本身没有退化——根 cgroup 有进程一直是非法的，只是旧版本睁一只眼闭一只眼。

### 无效的 workaround

网上常见的 `loginctl enable-linger 1000` **无效**，实测后 unit 仍是 failed。手动 `rmdir` 那个 cgroup 也不行，恒返回 EBUSY。`wsl --terminate` 重启发行版后，幽灵条目立刻重新出现——不是陈旧残留，是每次开机必现。

### 影响范围

日常使用不受影响（shell、编译、`sudo systemctl` 全正常）。但这些会废掉：

- `systemctl --user`、用户级 service、session D-Bus
- **fcitx5 输入法**（依赖 systemd user service）。绕路**可行但不止一步**：除了在 shell 启动时 `fcitx5 -d` 直接拉起，还必须自己补一条 session D-Bus，否则进程在跑却没有输入法。完整写法与取证见[第四节 4.8](#48-步骤-7fcitx5-绕路方案可行但比预想的多一件事)
- **rootless podman**（Fedora 上最容易撞到的一个）

### 各发行版 systemd 版本对照

| 发行版 | systemd | 状态 |
| :--- | :--- | :--- |
| Ubuntu 24.04 LTS | 255 | 可用 |
| Fedora 40 | 255 | 可用，但已 EOL |
| Fedora 41 / 42 / 43 / 44 | 256 / 257 / 258 / 259 | 全部中招 |

**不建议为此回退发行版。** 唯一能用的 Fedora 是 40，已停止安全更新——拿"没有 CVE 补丁"换"user session 能起来"不划算。要保守的 RPM 系应该选 AlmaLinux / Rocky（9.x 是 systemd 252），而不是老 Fedora。

> **这条对 Ubuntu 是预告片。** 24.04 LTS 安全只是因为它停在 systemd 255，**差一个版本**。Ubuntu 26.04 LTS 的 systemd 在 257 一线，升上去会在主力发行版上复现同样的故障。
>
> **在 WSL 侧修好之前，不要把 WSL 里的 Ubuntu 升到 26.04。**

相关上游：[microsoft/WSL#11857](https://github.com/microsoft/WSL/issues/11857)（systemd ≥ 256 需要纯 cgroup v2）、[microsoft/WSL#40519](https://github.com/microsoft/WSL/pull/40519)（根 cgroup / EBUSY 诊断）、[microsoft/WSL#12597](https://github.com/microsoft/WSL/issues/12597)、[microsoft/WSL#13053](https://github.com/microsoft/WSL/issues/13053)。

---

## 二、`binfmt_misc` 是内核全局的

装了两个及以上发行版时必读。所有发行版共用一张 binfmt 注册表，一个发行版的启停会摘掉别人的 `WSLInterop`。

完整说明与守护配置见 [`setup/README.md`](setup/README.md) 步骤 1.3 与
[`../agent/skills/wsl-windows-command/references/cross-distro.md`](../agent/skills/wsl-windows-command/references/cross-distro.md)。

十秒自证：在发行版 A 注册一个哨兵，然后去发行版 B 列目录，它就在那儿。

```bash
sudo sh -c 'echo ":ZZSentinelProbe:M::\x7fELF-SENTINEL::/bin/true:" > /proc/sys/fs/binfmt_misc/register'
```

---

## 三、跨发行版共享文件：走 `/mnt/wsl`，不是 `\\wsl.localhost`

发行版之间共享虚拟机但不共享挂载命名空间：对方的挂载不出现在 `/proc/self/mountinfo`，PID 互不可见。唯一的例外是 `/mnt/wsl`——一块以 **shared** 方式挂进每个 WSL2 发行版的 tmpfs。**目标**落在 `/mnt/wsl` 下面的 bind mount 会传播到所有其他发行版，包括之后才启动的。Windows 19041 就带了，Docker Desktop 一直这么干。

```bash
sudo mount --bind / /mnt/wsl/Ubuntu      # 源随便挑，目标必须在 /mnt/wsl 下；跨发行版调用要加 -u root
```

2026-09-20 在本机（WSL 2.7.14.0 / 内核 6.18.33.2 / Ubuntu 24.04.4 + Fedora 44）双向实测通过：读写都行，两边 uid 都是 1000 所以非 root 也能写。同一批文件（2313 个、21.6 MB）读全量，bind mount 用 0.97 s，绕 `\\wsl.localhost` + `powershell.exe` 要 22.5 s。

`\\wsl.localhost\<distro>\...` 是 **Windows** 侧的 UNC 路径，只有 Windows 进程能走，从另一个发行版的 Linux 侧够不着，顺着 `/mnt/c` 往上爬也不行。它只在「不想启动对方」或「调用方本来就是 Windows 进程」时才划算。

两个坑：`/mnt/wsl` 是 tmpfs，`wsl --shutdown` 之后挂载点全没，要靠 `/etc/fstab` 或 profile 重建；而 `wsl --terminate` **不**解除别的发行版持有的 bind mount——`wsl -l -v` 显示 `Stopped`，写进去的东西照样落盘。

完整版（含启动顺序、`automount root = /` 的静默失效、UID 不对齐）见 [`../agent/skills/wsl-windows-command/references/cross-distro.md`](../agent/skills/wsl-windows-command/references/cross-distro.md) 第 2 节。

---

## 四、安装步骤的发行版差异（Fedora 44）

2026-09-20 在 Fedora Linux 44（`VARIANT_ID=wsl`、dnf5 5.4.1.0、systemd 259）上把
[`setup/README.md`](setup/README.md) 的步骤 2～7 完整跑通一遍，本节是实测结果。
对照组是同一台宿主机上的 Ubuntu 24.04（参考实现），表格里的 Ubuntu 列都是当场查的，不是回忆。

> 步骤 1（`wsl.conf` / `fstab` / binfmt 守护）与发行版无关，原样可用。

### 4.1 一句话总结

**四层 shell 配置本身几乎是发行版中立的**：`shell_wslfn`、`zshenv`、`zshrc` 一个字都不用改，
`shell_common` 只有一处（第 8 节）需要加守卫。真正的差异全在**包管理和系统骨架**上。

### 4.2 原样可用的部分

| 步骤 | 内容 |
| :--- | :--- |
| 2 | metalink 换源的 `sed` **精确匹配** Fedora 44 的 `fedora.repo` / `fedora-updates.repo`，一次成功 |
| 3 | oh-my-zsh 安装脚本、`zsh-autosuggestions` 克隆，发行版无关 |
| 4 | `shell_wslfn` / `zshenv` / `zshrc` 逐字节原样可用 |
| 4 | `~/.bashrc` 里 `bash_completion` 那段的第一个分支命中（Fedora 同样提供 `/usr/share/bash-completion/bash_completion`） |
| 4 | `debian_chroot` 相关几行在 Fedora 上是无害死代码 |
| 5 | nvm / uv / conda 三个 `curl | sh` 旁路安装，发行版无关 |
| 6 | `gh` 在 Fedora 官方仓库里（2.97.0），不用加第三方源 |

**PPA 删掉不损失任何东西**：Fedora 仓库的 git 就是 **2.55.0**，与 Ubuntu 装完 `ppa:git-core/ppa`
之后的版本**完全一致**。参考文档里那条「Fedora 仓库的 git 本来就足够新」说得偏保守了，是等价，不是够用。

### 4.3 步骤 2：包名与缺失的基础命令

```bash
sudo dnf install -y zsh curl wget git git-filter-repo jq
sudo dnf group install -y development-tools    # 不是 groupinstall，dnf5 已移除
sudo dnf install -y gawk xz                    # 见下，非补不可
```

**Fedora WSL 镜像比 Ubuntu 精简得多，缺的不只是开发工具：**

| 命令 | Ubuntu 24.04 | Fedora 44 WSL | 后果 |
| :--- | :--- | :--- | :--- |
| `awk` | 有 | **无** | **nvm 直接挂**，见下 |
| `xz` | 有 | **无** | node 官方 tarball 是 `.tar.xz` |
| `bc` | 有 | 无 | 一些脚本会用 |
| `openssl`(CLI) | 有 | 无 | 按需 |

`awk` 缺失导致的 nvm 报错**极具误导性**，会把人带到完全错误的方向：

```
/home/<user>/.nvm/nvm.sh: line 2241: awk: command not found
$NVM_NODEJS_ORG_MIRROR and $NVM_IOJS_ORG_MIRROR may only contain a URL
Version '' (with LTS filter) not found - try `nvm ls-remote --lts` to browse available versions.
```

真正的错误是第一行，但最后一行在指挥你去查镜像和版本列表。**装上 `gawk` 后一次成功。**

**`git-filter-repo` 的安装形态不同**，这个不改命令但改用法：

| | 路径 | 可用调用 |
| :--- | :--- | :--- |
| Ubuntu | `/usr/bin/git-filter-repo` | `git filter-repo` 和 `git-filter-repo` 都行 |
| Fedora | `/usr/libexec/git-core/git-filter-repo` | **只有 `git filter-repo`** |

Fedora 把它放进 git 的 exec-path，裸命令名不在 `PATH` 里。脚本里写了 `git-filter-repo` 的要改成子命令写法。

### 4.4 步骤 3：`chsh` 的两个坑（参考文档在这里说错了）

交接文档写的是「`chsh -s "$(which zsh)"` 直接可用」。**实测不可用，而且是两个独立的原因。**

**坑一：`which zsh` 给出的路径不在 `/etc/shells` 里。**

| | `which zsh` | 在 `/etc/shells` 中？ |
| :--- | :--- | :--- |
| Ubuntu 24.04 | `/usr/bin/zsh` | 是 |
| Fedora 44 | **`/usr/sbin/zsh`** | **否**（只列了 `/usr/bin/zsh`、`/bin/zsh`） |

Fedora 做了 usrmerge（`/usr/sbin -> bin`），且 `/usr/sbin` 排在 `PATH` 前面，所以 `which` 返回
`/usr/sbin/...`。它和 `/usr/bin/zsh` 是同一个文件，但 `chsh` 做的是**字符串**比对，不解析符号链接。

**坑二：`chsh` 无条件要交互密码**，AI Agent / 脚本场景必然失败：

```
$ chsh -s "$(which zsh)" < /dev/null
Password: chsh: Authentication failure
```

**正确写法（两个坑一起绕开）：**

```bash
sudo chsh -s /usr/bin/zsh "$USER"
```

> 交接文档另一条判断是**对的**：`chsh` 确实**不需要** `util-linux-user`。
> 实测 `rpm -qf /usr/bin/chsh` → `util-linux-2.41.3-12.fc44`，Fedora 44 已把它并回主包。
> 网上让你先装 `util-linux-user` 的说法已经过时。

### 4.5 步骤 4：系统骨架的两处差异

**（1）`~/.bashrc` 必须补 `. /etc/bashrc`——确认需要。**

| | 全局 bashrc | 谁来加载 `/etc/profile.d/*.sh` |
| :--- | :--- | :--- |
| Ubuntu | `/etc/bash.bashrc` | `/etc/profile` |
| Fedora | **`/etc/bashrc`** | **`/etc/bashrc` 自己** |

两边文件名不同且互不存在。直接铺 Debian 血统的 `~/.bashrc` 会**静默**掐断 Fedora 这条链。
补丁加在非交互早退守卫之后，**带守卫因此在 Ubuntu 上是无害空操作**，已直接并进
[`setup/files/bashrc`](setup/files/bashrc)：

```bash
[ -f /etc/bashrc ] && . /etc/bashrc
```

**（2）`~/.profile` 在 Fedora 上是死文件。** 这条交接文档没提到。

Fedora 的骨架自带 `~/.bash_profile`，而 bash 登录时**只读第一个存在的**
`~/.bash_profile` → `~/.bash_login` → `~/.profile`。Ubuntu 没有 `~/.bash_profile`，所以
`~/.profile` 生效；Fedora 有，所以 `cp files/profile ~/.profile` **铺了也不会被读**。

实际影响很小——Fedora 的 `~/.bashrc` 自己就把 `$HOME/.local/bin` 和 `$HOME/bin` 加进了 `PATH`，
和 `files/profile` 想做的事重合。但**别误以为是 `~/.profile` 在起作用**，改它不会有任何效果。

**（3）`shell_common` 第 8 节会在每个交互 shell 里报错。** 这条交接文档也没提到。

| | `dbus-launch` | `gnome-keyring-daemon` |
| :--- | :--- | :--- |
| Ubuntu | 有 | 有 |
| Fedora WSL | **无**（在 `dbus-x11`） | **无**（在 `gnome-keyring`） |

原文只给 keyring 那行加了 `2>/dev/null`，`dbus-launch` 那行**没有任何保护**，于是每开一个
交互 shell 就吐一次 `dbus-launch: command not found`。已改成 `command -v` 守卫并并进
[`setup/files/shell_common`](setup/files/shell_common)，在两个发行版上都正确。

### 4.6 步骤 5：corepack 默认版本已经漂走

`corepack enable pnpm` 现在装的是 **pnpm 12.4.2**，**直接违反**
[`setup/README.md`](setup/README.md) 步骤 5「pnpm 留在 11.x」的决定。
这不是 Fedora 差异，是上游默认值变了——`latest` 已指向 12。

```bash
corepack prepare pnpm@11.27.0 --activate    # 必须显式钉，否则拿到 12.x
```

注意 `11.27.0` 挂在 `next-11` 标签上，`latest-11` 停在 `11.26.0`。

### 4.7 步骤 6：wslu 缺失，且 `BROWSER` 不能是 shell 函数

`wslu` 确实不在 Fedora 仓库里（`wslview` 缺失属实）。但交接文档推荐的方案
——「在 `~/.shell_wslfn` 里加个包 `powershell.exe Start-Process` 的函数，把 `BROWSER` 指向它」
——**行不通**，原因是 `gh` 根本不经过 shell：

`gh` vendor 了 `github.com/cli/browser` v1.3.0 + `kballard/go-shellquote`，拿到 `$BROWSER` 后
用 shellquote 切词，然后对 `argv[0]` 调 `exec.LookPath()`。**全程没有 shell 参与**，
shell 函数对它完全不可见，只会得到 `executable file not found in $PATH`。

取证（不依赖记忆，在本机 `gh` 二进制里直接查）：

```bash
strings /usr/bin/gh | grep -E 'cli/browser|go-shellquote'
strings /usr/bin/gh | grep 'executable file not found'
```

**所以 `BROWSER` 必须指向真实可执行文件。** 实现放在
[`setup/files/bin/wslview`](setup/files/bin/wslview)，部署到 `~/.local/bin/wslview`。

**刻意沿用 `wslview` 这个名字**：`shell_common` 里原有的守卫

```sh
if command -v wslview >/dev/null 2>&1; then export BROWSER=wslview; fi
```

于是**一个字都不用改**就认到它，`shell_common` 保持发行版中立。实测 `BROWSER=wslview`
自动生效，`wslview https://example.com` 成功唤起 Windows 默认浏览器。

### 4.8 步骤 7：fcitx5 绕路方案可行，但比预想的多一件事

**结论：可行。** 但交接文档给的两行（装包 + 在 `~/.zshrc` 里 `fcitx5 -d`）**不够**。

```bash
sudo dnf install -y fcitx5 fcitx5-chinese-addons fcitx5-configtool
sudo dnf install -y dbus-daemon      # 交接文档没提，但少不了
```

`fcitx5-gtk3` / `fcitx5-qt6` 会作为依赖自动装上，不用显式列。

**缺的那件事是 session D-Bus。** 只把 `fcitx5 -d` 拉起来，进程确实在跑，但：

```
$ fcitx5-remote
E remote.cpp:160] Could not open DBus connection: Failed to create dbus connection
```

`fcitx5-configtool` 和 GTK/Qt 输入法模块**全都走 session bus** 找 fcitx5 守护进程。
没有总线 = 有进程但没有输入法。而 session bus 正常是由 `systemd --user` 拉起的，
本机 `user@1000.service` 起不来（第一节），所以这一环也得自己补。

#### 这里有个**会吞掉守卫**的陷阱

WSL 会**无条件**往每个 shell 里导出：

```
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
```

指的正是 `systemd --user` 本该创建的那个 socket。**但在这台机器上那个 socket 永远不存在。**
于是这个变量**被设置了、却是死的**。

> **别把这条理解成"WSL 总是导出一个死路径"。** 在同一台宿主机的 Ubuntu 24.04 上实测，
> `/run/user/1000/bus` **是存在的**——因为那里 `user@1000.service` 正常启动。
> 换句话说，socket 在不在，取决于 **systemd user session 起没起来**（见第一节），
> 这是那个 bug 的下游症状，不是 WSL 的普遍行为。判 socket 不判变量之所以正确，
> 恰恰因为它在两种情况下都对。后果是任何这种形状的守卫都会**静默地什么都不做**：

```sh
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then ... fi    # 永远不成立，看起来却很对
```

**一律判 socket，不要判变量。** 实测踩过一次：变量有值、总线不存在、fcitx5 起来了但没有输入法，
而且不报任何错。

#### 为什么用固定路径而不是 `dbus-launch`

`dbus-launch` **每个 shell 开一条私有总线**。开三个终端就是三条互不相通的总线，
在第二个终端里启动的 GUI 程序**看不到**第一个终端上那个 fcitx5。
用 `$XDG_RUNTIME_DIR/bus` 这个固定路径就只有一条总线——而且它正是 `systemd --user`
会用的路径，所以已经认这个地址的程序（包括上面那个 WSL 预设的变量）自动就对上了。

#### 可用的写法（放 `~/.zshrc`，交互 shell 才需要输入法）

```sh
# Test the SOCKET, never the variable. WSL exports
#   DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
# into every shell unconditionally, pointing at the socket that
# systemd --user would have created. Here user@1000.service never starts, so
# that socket does not exist and the variable is permanently stale. Any guard
# of the form `if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]` therefore does nothing at
# all, silently, while still looking correct.
if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ]; then
  _bus_path="$XDG_RUNTIME_DIR/bus"

  if [ ! -S "$_bus_path" ] && command -v dbus-daemon >/dev/null 2>&1; then
    dbus-daemon --session --address="unix:path=$_bus_path" \
      --nopidfile --fork >/dev/null 2>&1
  fi

  if [ -S "$_bus_path" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$_bus_path"

    # Needs a display (WSLg) too; stays quiet when there is none.
    if [ -n "${DISPLAY:-}" ] && command -v fcitx5 >/dev/null 2>&1; then
      pgrep -x fcitx5 >/dev/null 2>&1 || (fcitx5 -d >/dev/null 2>&1 &)
    fi
  fi

  unset _bus_path
fi
```

**没有放进 `files/zshrc`**：它是「systemd user session 坏掉」的补丁，不是通用配置。
Ubuntu 上 `systemd --user` 正常，这段虽然无害但纯属多余。需要的人从这里抄。

#### 还要补输入法本身

装完之后 `~/.config/fcitx5/profile` 里**只有 `keyboard-us`**，拼音装了但没进输入法组，
也就是说开箱状态打不出中文。加一段：

```ini
[Groups/0/Items/1]
Name=pinyin
Layout=
```

（`DefaultIM` 保持 `keyboard-us`，用 Ctrl+Space 切换。改 profile 前先停掉 fcitx5，否则退出时会被覆写。）

#### 实测结果

| 检查项 | 结果 |
| :--- | :--- |
| 冷启动：删掉 socket 与进程，开一个交互 zsh | 总线与 fcitx5 自动拉起 |
| 幂等：连开 4 个交互 shell | `fcitx5` 进程数恒为 **1** |
| `fcitx5-remote` | 返回 `0`（连上了，输入法待机），不再报 D-Bus 错 |
| 输入法组 | `('us', [('keyboard-us', ''), ('pinyin', '')])` |
| `fcitx5-configtool` | 窗口正常弹出（WSLg 侧标题 `Fcitx Configuration (Fedora)`） |
| `GTK_IM_MODULE=fcitx` 是否匹配 | 匹配。`immodules.cache` 同时注册了 `fcitx` 和 `fcitx5` 两个 id，`shell_common` 第 7 节原值正确 |

> **尚未验证**：在 GUI 程序里实际敲出中文、候选词窗口弹出。这一步需要真人在键盘前，
> 上面所有检查都只能证明「链路各环节都通」。

> 另有一个 `dbus-daemon` 进程属正常：`at-spi2` 无障碍总线由 session bus 自动激活，不是重复的会话总线。

### 4.9 交接文档判断错误的地方（汇总）

| 交接文档的说法 | 实测 |
| :--- | :--- |
| `chsh -s "$(which zsh)"` 直接可用 | **错**。`/usr/sbin/zsh` 不在 `/etc/shells`，且 `chsh` 无条件要密码。用 `sudo chsh -s /usr/bin/zsh "$USER"` |
| 步骤 6 方案 2：`BROWSER` 指向 `shell_wslfn` 里的函数 | **错**。`gh` 用 `exec.LookPath`，不起 shell，函数不可见。必须是真实可执行文件 |
| 步骤 7 只要「装包 + `fcitx5 -d`」 | **不完整**。还缺 session D-Bus，否则有进程无输入法；且拼音默认没进输入法组 |
| `PATH` 里仍有 41 条 `/mnt/c`，需 `wsl --shutdown` 才生效 | **已过期**。接手时 `wsl.conf` / `fstab` 早已生效（`/mnt/c` 计数为 **0**，C/D/E 已按 fstab 挂好），**没有执行任何 shutdown** |
| 基础包清单 | **不全**。漏了 `gawk`、`xz`（nvm 因此直接失败） |
