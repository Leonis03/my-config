# PTY 伪终端与 /proc/self/exe 机制深剖

在 Android chroot 容器中运行 AI 编码助手（如 Antigravity CLI、Claude Code）或自动化构建工具时，常会遇到两类与底层系统调用紧密相关的典型报错：
1. `failed to get executable path: readlink /proc/self/exe: no such file or directory`
2. `failed to create PTY: open /dev/ptmx: no such device`

本篇深入剖析其内核机理，说明为什么这两项是容器内 CLI 生态正常运转的绝对底线，并介绍基于独立 `tmpfs` 的 `/dev` 架构方案。

---

## 1. `execve(2)` 与 `/proc/self/exe` 的解耦与真相

### 1.1 内核原语的纯粹性
在 Linux 内核层面，进程派生的基石是 [`execve(2)`](https://man7.org/linux/man-pages/man2/execve.2.html) 系统调用：
```c
int execve(const char *pathname, char *const argv[], char *const envp[]);
```
* 内核在执行 `execve` 时，仅根据传入的 `pathname` 解析 VFS 目录树，读取目标 ELF 文件的 Header、Program Header Table，设置内存映射，加载动态链接器（如 `/lib/ld-linux-aarch64.so.1`），并跳转至程序入口点。
* **内核启动进程本身完全不需要 `/proc` 文件系统的参与**。一个静态编译的 C/Go 程序，在没有任何伪文件系统挂载的空 chroot 目录下，完全可以正常派生并执行。

### 1.2 现代高级语言运行时的自省依赖
然而，现代 CLI 工具（如 Go 编写的 Antigravity、Rust 工具链、Node.js 运行时）在应用层引入了强烈的自省需求：
* **二进制自我定位**：工具为了查找同目录下的配置文件、扩展插件、内嵌静态资产，必须获知自身运行时的绝对路径。
  * 在 Go 语言标准库中，[`os.Executable()`](https://pkg.go.dev/os#Executable) 在 Linux 下的实现就是：
    ```go
    func executable() (string, error) {
        return Readlink("/proc/self/exe")
    }
    ```
  * 在 Rust 中，[`std::env::current_exe()`](https://doc.rust-lang.org/std/env/fn.current_exe.html) 在 Linux 下同样直接读取 `/proc/self/exe`。
* **子进程派生与 IPC 协调**：当 Agent 派生执行工具（如子 runner、后台守护进程）时，需要用自身路径重新拉起或传递环境句柄。
* **报错触发点**：当 `/proc` 伪文件系统未挂载时，对 `/proc/self/exe` 发起 `readlink` 会直接收到内核返回的 `ENOENT`（No such file or directory）。上层运行器认为环境不完整，主动防御性报错退出。

> **核心结论**：
> 挂载 `/proc` **不是**为了给容器进程赋予更高权限，而是为了**满足现代语言运行时的自省与环境发现依赖**。

---

## 2. UNIX 98 PTY 架构与 `/dev/ptmx` 陷阱

### 2.1 传统 BSD 伪终端 vs UNIX 98 PTY
早期的 BSD 伪终端采用成对的静态设备节点（`/dev/ptyXX` 和 `/dev/ttyXX`），存在安全性差、并发受限、节点耗尽等严重缺陷。

现代 Linux 统一使用 UNIX 98 伪终端标准（PTS）：
* **Master 端**：统一通过打开主控制设备 `/dev/ptmx`（Pseudo Terminal Master Multiplexer）申请。
* **Slave 端**：由内核根据 Master 的打开动态在 `/dev/pts/` 目录下生成对应的从设备节点（如 `/dev/pts/0`, `/dev/pts/1`）。

### 2.2 为什么静态 `mknod /dev/ptmx` 会报 `ENODEV`？
许多初学者在自建 chroot 时，习惯于在容器的 `/dev` 下手动建立静态节点：
```bash
mknod -m 666 /dev/ptmx c 5 2
```
然而，在不挂载 `devpts` 文件系统的情况下，尝试打开该节点会立即报错：
```text
failed to create PTY: open /dev/ptmx: no such device
```
* **内核机制**：字符设备主设备号 5、次设备号 2 的驱动在被 `open` 打开时，内核驱动会尝试在当前的 `devpts` 实例中查找或分配一个新的 pty 编号。
* **驱动行为**：如果系统内没有挂载 `devpts` 伪文件系统，驱动无法找到与之绑定的 slave 命名空间，因此直接返回 `ENODEV`（No such device）。

---

## 3. 生产级架构：独立 `tmpfs` `/dev` 与 `devpts newinstance`

在 Android 宿主下，直接执行 `mount --bind /dev "$ROOT/dev"` 存在诸多隐患：
* Android 的 `/dev` 包含大量带有特定 SELinux 标签的硬件设备节点（如 binder、camera、ion、qseecom 等），容器内的包管理器或服务可能误读误写。
* Android 自身的终端应用（如 Termux）也在使用宿主的 `/dev/pts`，直接共用容易引发 slave 终端编号冲突或权限混乱。

### 3.1 最佳实践拓扑
启动脚本采用「独立 tmpfs + 精准软链 + 新实例 devpts」架构：

```bash
# 1. 在容器的 /dev 建立干净的独立 tmpfs
/system/bin/mount -t tmpfs -o mode=755,nosuid,nodev tmpfs "$ROOT/dev"
/system/bin/mkdir -p "$ROOT/dev/pts" "$ROOT/dev/shm"

# 2. 从 Android 宿主精准桥接基础字符设备
for node in null zero full random urandom tty console; do
    if [[ -e "/dev/$node" ]]; then
        /system/bin/ln -s "/android/dev/$node" "$ROOT/dev/$node"
    fi
done

# 3. 补全标准描述符软链
/system/bin/ln -s pts/ptmx "$ROOT/dev/ptmx"
/system/bin/ln -s /proc/self/fd "$ROOT/dev/fd"
/system/bin/ln -s /proc/self/fd/0 "$ROOT/dev/stdin"
/system/bin/ln -s /proc/self/fd/1 "$ROOT/dev/stdout"
/system/bin/ln -s /proc/self/fd/2 "$ROOT/dev/stderr"

# 4. 挂载独立 PTY 实例与共享内存
/system/bin/mount -t devpts -o newinstance,gid=5,mode=620,ptmxmode=666 devpts "$ROOT/dev/pts"
/system/bin/mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs "$ROOT/dev/shm"
```

* **`-o newinstance`**：创建全新的 UNIX 98 PTY 命名空间，终端编号从 `0` 重新独立计数，完全隔离宿主 Termux 的 PTY 实例。
* **`ptmxmode=666`**：允许任意 UID 读写 master 多路复用器。
* **`/dev/shm`**：POSIX 共享内存支撑（很多编译器与并发进程依赖）。

---

## 4. 极简 Pure-Bash PTY 探测机制

在无需依赖额外外部命令（如 `python`、`script`、`openvt`）的前提下，如何以零开销在 Shell 中探测 PTY 是否完全健康？

使用 Bash 自带的重定向操作符向 `/dev/ptmx` 申请双向文件描述符：

```bash
exec 3<>/dev/ptmx
echo "PTY: OK"
exec 3>&-
```

* **成功时**：文件描述符 3 成功绑定一个新分配的 PTY Master 端，退出码为 0。
* **失败时**：若 `devpts` 未挂载或权限不足，Bash 会直接抛出 `cannot open /dev/ptmx: No such device` 并返回非零退出码。
* 该技巧已被集成至 `debian --check` 启动自检逻辑中。

---

## 5. Agent 运行器的自愈死锁现象

### 5.1 死锁还原
在 AI 辅助运维场景下，经常出现以下戏剧性的一幕：
1. Agent 已经分析出容器内缺少 `/dev/pts` 挂载。
2. Agent 计划通过调用自身工具库中的 `run_command` 执行 `mount -t devpts ...` 来完成修复。
3. 工具调用直接失败，报错依然是：
   ```text
   failed to create PTY: open /dev/ptmx: no such device
   ```

### 5.2 为什么无法通过 `run_command` 自愈？
Agent 的命令执行框架（如基于 Go `creack/pty` 或 Node.js `node-pty` 实现的子进程控制层）在派生任何命令前，有一套固定的执行生命周期：
```text
Agent 发起 run_command
  │
  ├─ 1. pty.Open() -> open("/dev/ptmx")  <=== 此处由于 devpts 未挂载，系统直接抛出 ENODEV
  │     └─ 异常被工具框架拦截，向上层模型返回错误，终止流程
  │
  └─ 2. 只有第 1 步成功，才会调用 os.StartProcess / execve(mount, ...)
```
因为错误发生在调用 `execve` **之前**的宿主环境准备阶段，因此 Agent 绝对无法通过需要 PTY 驱动的工具来自主完成 PTY 驱动本身的修复。

### 5.3 解决指引
所有涉及 `/proc`、`/dev/pts`、基础设备节点的挂载操作，**必须封装在宿主侧的容器启动器（Launcher）或宿主运维脚本中**，确保进入容器前底层 VFS 基础设施已 100% 健全。
