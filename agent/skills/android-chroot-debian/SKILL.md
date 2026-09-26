---
name: android-chroot-debian
description: >-
  Diagnose, configure, and troubleshoot root Debian chroot environments on Android (Termux).
  Use when running CLI AI agents (agy, Claude Code) or development tools inside an Android
  chroot container, when encountering "readlink /proc/self/exe: no such file or directory" or
  "failed to create PTY: open /dev/ptmx: no such device", when navigating unshare -m Mount Namespace
  isolation traps where peer processes cannot see updated mounts, when handling Magisk ramdisk EINVAL
  mount errors, or when deploying a robust container launcher with automated health checks.
---

# Android Root chroot Debian (Termux) 容器运维与排障指南

在已 Root 的 Android 设备上，通过 Termux 部署 `chroot` Debian 容器是搭建本地 Linux 开发环境与运行 AI Agent（如 Claude Code、Antigravity CLI / `agy`）的终极方案。

然而，从 Android Bionic 与 glibc 的动态链接冲突，到共享内核、Magisk SELinux 域策略、Linux Mount Namespace 隔离以及 UNIX 98 PTY 伪终端机制的叠加，会引发一系列极具隐蔽性的底层故障。本 skill 总结真实实战中的排错经历、底层机理与生产级封装方案。

---

## 1. 核心架构认知与特权边界

在排查任何故障前，必须建立精确的特权与架构心智模型，避免概念混淆：

### 1.1 架构起源：为什么 Termux 无法原生运行 `agy`？
* **现象**：在 Termux 中通过官方脚本安装 `agy` 后，即便二进制文件存在且具备执行权限（755），直接运行仍报错：
  ```text
  bash: /data/data/com.termux/files/home/.local/bin/agy: cannot execute: required file not found
  ```
* **底层根因**：
  * 使用 `readelf -l` 审查程序头表，发现其动态解释器（`PT_INTERP`）为：
    `[Requesting program interpreter: /lib/ld-linux-aarch64.so.1]`
  * **Android 原生使用 Bionic libc**，动态链接器为 `/system/bin/linker64`。宿主中根本不存在 `/lib/ld-linux-aarch64.so.1`，内核 `execve(2)` 查找解释器失败返回 `ENOENT`，Shell 统一表现为「找不到文件」。
  * **结论**：所有基于 glibc 编译的 Linux 工具链无法在 Termux 原生运行，必须构建 glibc 容器环境。

### 1.2 chroot 容器的特权拓扑
* **chroot 共享 Android 内核**：`chroot(2)` 仅仅改变了当前进程及其子进程树的 VFS 根目录视角（root directory），**不是虚拟机（VM）**，没有硬件虚拟化层，也不自带独立的内核空间。容器内的所有进程直接受宿主 Android Linux 内核调度。
* **凭据与权能**：
  * **用户身份**：通过 `su` 启动后，容器内进程具备真实的 `uid=0(root) gid=0(root) groups=0(root)`。
  * **Linux Capabilities**：继承自宿主 Magisk root 进程，具备全部 41 项内核权能（`CapPrm / CapEff / CapBnd: 000001ffffffffff`）。
  * **SELinux 域**：受宿主内核 SELinux 约束，通常处于 `u:r:magisk:s0` 或 `u:r:su:s0` 域。
* **文件系统直通风险**：
  * 容器中挂载的 `/android`（宿主根）或 `/storage/emulated/0` 是真实底层文件系统的直接映射（F2FS / ext4 / sdcardfs / fuse）。
  * 在容器中对 `/android` 或内部存储路径的写操作会**立即且永久修改 Android 宿主数据**，不存在沙箱写时复制（COW）保护。

### 1.3 工具权限 vs 系统权限的区别
* **`agy --dangerously-skip-permissions` 的定位**：
  * 该参数仅为 Antigravity CLI 工具自身的应用层安全策略，用于跳过模型调用工具（如执行 Shell 命令、修改文件）时在终端向用户弹窗等待回车确认的流程。
  * **它绝不会提升系统层面的任何 Linux 权限**。系统权限严格由 Linux UID、Capabilities 以及 Android SELinux 策略决定。

---

## 2. 核心踩坑与底层取证分析

### 2.1 踩坑一：`/proc` 缺失导致的 CLI 运行时自省瘫痪
* **故障现象**：
  在 chroot 容器内启动 `agy` 或派生子命令时，工具直接报错崩溃：
  ```text
  failed to get executable path: readlink /proc/self/exe: no such file or directory
  ```
* **底层机制分析**：
  * **内核层面**：Linux 系统的进程派生原语 [`execve(2)`](https://man7.org/linux/man-pages/man2/execve.2.html) 仅需目标可执行文件路径、ELF 头结构及动态链接器（如 `ld-linux.so`），**内核派生进程本身完全不依赖 `/proc`**。静态链接二进制或常规 C 程序在没有 `/proc` 的裸 chroot 下完全可以正常 `exec`。
  * **运行时自省机制**：现代高级语言运行时（如 Go 的 `os.Executable()`、Rust 的 `std::env::current_exe()`、Node.js 运行时及许多 CLI 工具链）在启动、自省或准备 IPC 管道时，都会显式调用 `readlink("/proc/self/exe")` 获取自身二进制文件的规范化绝对路径。
  * **报错归因**：当 chroot 根目录下的 `/proc` 未挂载内核 proc 伪文件系统时，`readlink` 返回 `ENOENT`，导致运行器认为环境损坏而主动中止。
* **结论与处置**：
  * 挂载 `/proc` 是为了**补全现代 CLI 工具链的运行时自省依赖**，而非进行权限提升。
  * 修复命令（宿主端）：`mount -t proc proc "$DEBIAN_ROOT/proc"`。

### 2.2 踩坑二：PTY 伪终端缺失与终端分配失败
* **故障现象**：
  挂载 `/proc` 后，命令执行器启动持久化终端（Persistent Terminal）或交互式子 shell 时报错：
  ```text
  failed to create PTY: open /dev/ptmx: no such device
  ```
* **底层机制分析**：
  * 交互式命令与子进程终端控制依赖 UNIX 98 伪终端（PTY）。
  * 仅仅存在一个普通的 `/dev/ptmx` 字符设备节点是**不可用**的。现代 Linux 内核要求必须挂载 `devpts` 伪文件系统。
  * 若仅建立节点而未正确挂载 `devpts`，打开 `/dev/ptmx` 时内核驱动找不到对应的 master 实例管理器，直接向调用方返回 `ENODEV`（No such device）。
  * 正确挂载 `devpts` 时，还必须赋予正确的挂载选项，尤其是 `newinstance`、`ptmxmode=666` 和 `mode=620`，并建立 `/dev/ptmx -> pts/ptmx` 软链接。
* **处置方案**：
  ```bash
  mount -t devpts -o newinstance,gid=5,mode=620,ptmxmode=666 devpts "$DEBIAN_ROOT/dev/pts"
  ln -sf pts/ptmx "$DEBIAN_ROOT/dev/ptmx"
  ```

### 2.3 踩坑三：Agent 容器内自愈死锁（“先有鸡还是先有蛋”）
* **故障现象**：
  当运行在容器内的 AI Agent 发现 `/dev/ptmx` 损坏时，即便 Agent 知道修复命令，也无法通过其内置的 `run_command` 工具自愈。
* **死锁根因**：
  * Agent 执行 `run_command` 时，为了保证命令输出能够流式获取并保留交互控制能力，执行器在调用底层系统调用派生子进程前，必须先在操作系统中分配一个 PTY 设备。
  * 由于容器内尚未挂载 `devpts`，执行器在调用 `open("/dev/ptmx")` 这一步就抛出异常，整个工具调用在派生进程之前就已被系统中断。
  * **结论**：**基础设施级的挂载故障必须在宿主环境（Termux）修复**，容器内的 Agent 无法跨越这一死锁。

### 2.4 踩坑四：Mount Namespace (`unshare -m`) 隔离与会话不同步
* **故障现象**：
  宿主在 Termux 中更新了 `debian` 启动脚本，并在 Termux 终端中执行 `debian --check` 验证通过（显示 PTY 与 Android 挂载点完全就绪）；但原本已经在运行的 `agy` 实例再次执行命令时，依然报 `open /dev/ptmx: no such device`。
* **取证排查（`/proc` 进程树分析）**：
  检查当前全新启动的 `agy` 进程，发现进程树结构如下：
  ```text
  /system/bin/unshare -m '$HOME/.local/bin/debian' --root (PID 22643)
    └─ /bin/bash -l (PID 22646)
        └─ agy --dangerously-skip-permissions (PID 20213)  <-- 新启动的 agy
  ```
* **根因剖析**：
  1. **Namespace 隔离特性**：`/system/bin/unshare -m` 为会话创建了**独立的 Mount Namespace**。在 Termux 重新执行 `debian --check` 是在一个全新的 Namespace 中验证的。
  2. **父进程 Bash 未退出**：用户在原有终端里按 `Ctrl+C` 重新启动了 `agy`，但**没有退出外层的 `/bin/bash -l`（PID 22646）**。
  3. **挂载表未更新**：由于父进程一直在运行，它仍然被困在最初的 `unshare -m`（PID 22643）命名空间中。查看当前进程可见的 `/proc/mounts`，挂载点依旧停留在未挂载 `/dev/pts` 的旧状态。
* **解决铁律**：
  更新挂载脚本后，**必须彻底退出（`exit`）旧的 shell 会话**，销毁旧 Mount Namespace，再通过新脚本重新进入。

### 2.5 踩坑五：Android 宿主递归挂载缺失与 Magisk Ramdisk `EINVAL`
* **故障现象 1**：宿主直接执行 `mount --bind / "$ROOT/android"` 后，容器内发现 `/android/system` 或 `/android/data` 为空目录。
  * **根因**：Android 系统的 toybox/toolbox `mount` 命令**不支持 `--rbind` 递归绑定挂载**。必须通过动态遍历 `/proc/mounts` 分别挂载子分区。
* **故障现象 2**：在遍历挂载时，脚本报 `Invalid argument (EINVAL)` 崩溃退出：
  ```text
  mount: '/debug_ramdisk/.magisk/preinit' -> '...': Invalid argument (EINVAL)
  ```
  * **根因**：Magisk 早期启动在 Android 内核中注入的内存块特殊设备不支持常规 VFS bind mount。
  * **应对策略**：遍历挂载时显式过滤 `/debug_ramdisk/.magisk/preinit`、`/data/*`（`/data` 整体挂载）与转义字符。

---

## 3. 标准生产级封装方案：`debian` 启动器

在 Termux 宿主端部署 `$HOME/.local/bin/debian` 启动脚本，实现：
1. **自动提权与 Mount Namespace 隔离**：未带 `--root` 启动时自动以 `su -c "/system/bin/unshare -m ..."` 重启自身，容器退出时自动卸载，绝不污染 Android 宿主。
2. **私有挂载传播保护**：执行 `/system/bin/mount -o rprivate none /`，杜绝任何容器内挂载事件反向泄漏。
3. **Android 宿主动态透传**：动态解析 `/proc/mounts` 逐一映射 `/system`、`/data`、`/apex`、`/storage`，同时自动跳过 Magisk ramdisk。
4. **独立 tmpfs `/dev` 系统**：
   * 在容器 `/dev` 挂载独立 `tmpfs`，将核心字符设备（`null`, `zero`, `urandom`, `tty`, `console` 等）软链至 `/android/dev/`。
   * 挂载独立 `devpts`（参数 `-o newinstance,gid=5,mode=620,ptmxmode=666`）与 `tmpfs` `/dev/shm`。
5. **一键轻量自检模式 (`debian --check`)**：
   通过纯 Bash 文件描述符重定向 `exec 3<>/dev/ptmx` 探测 PTY 可分配性，全面核验 procfs、UID 及 Android 宿主目录。

### 3.1 启动器部署
完整脚本见 [`scripts/debian-chroot-launcher.sh`](scripts/debian-chroot-launcher.sh)。在 Termux 中部署方式：

```bash
mkdir -p "$HOME/.local/bin"
cp "$HOME/.gemini/config/skills/android-chroot-debian/scripts/debian-chroot-launcher.sh" "$HOME/.local/bin/debian"
chmod 700 "$HOME/.local/bin/debian"
```

### 3.2 极简 Debian 容器构建
若需从零构建 minimal 容器，可运行 [`scripts/bootstrap-debian-termux.sh`](scripts/bootstrap-debian-termux.sh)。关键配置包括清华 TUNA 镜像源、Debian Trixie Keyrings 验证、Android DNS 属性继承（`getprop net.dns1`）与 `/tmp` 1777 权限设置。

---

## 4. 环境健康核验清单 (Checklist)

在进入 Debian 容器后，可执行以下命令进行端到端全量自检（或在容器内运行 [`scripts/verify-chroot-env.sh`](scripts/verify-chroot-env.sh)）：

| 检查项 | 验证命令 | 预期输出 / 正常标准 | 异常处理 |
| :--- | :--- | :--- | :--- |
| **UID / GID** | `id` | `uid=0(root) gid=0(root) groups=0(root)` | 未通过 `su` 提权启动 |
| **Capabilities** | `grep -E '^Cap' /proc/self/status` | `CapEff: 000001ffffffffff` (41 项满权) | 宿主 su/Magisk 策略受限 |
| **SELinux 域** | `cat /proc/self/attr/current` | `u:r:magisk:s0` 或 `u:r:su:s0` | 处于受限 Android App 沙箱域 |
| **自省路径** | `ls -l /proc/self/exe` | 指向当前 shell (如 `/bin/bash` 或 `/bin/ls`) | `/proc` 未挂载 |
| **PTY 系统** | `exec 3<>/dev/ptmx && echo OK` | 输出 `OK`，且当前 `tty` 输出 `/dev/pts/<N>` | `devpts` 未挂载或参数缺 `ptmxmode=666` |
| **命令调度** | `run_command` (Agent 层面) | 正常执行且退出码 `0` | PTY 分配失败或旧 Namespace 未退出 |
| **Android 互通** | `ls -d /android/data /android/system` | 目录存在且可读 | 宿主 `/proc/mounts` 映射循环未执行 |

---

## 5. 更多深度参考

* [Bionic vs glibc ELF 解释器冲突 (`cannot execute: required file not found`)](references/bionic-vs-glibc-elf.md)
* [Mount Namespace 隔离与会话不同步陷阱分析](references/mount-namespace-gotchas.md)
* [PTY 伪终端与 /proc/self/exe 机制深剖](references/pty-and-proc-internals.md)
