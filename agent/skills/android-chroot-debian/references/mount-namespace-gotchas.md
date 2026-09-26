# Mount Namespace (`unshare -m`) 隔离与会话不同步陷阱分析

在 Android 宿主上使用 `chroot` 时，最佳实践是利用 Linux 的 Mount Namespace（挂载命名空间）来封装容器的挂载点。然而，如果在多会话、长驻留 Agent 或更新配置脚本时对 Namespace 的生命周期与隔离语义理解不透彻，极易陷入「明明脚本已改且测试通过，正在运行的工具却依然报错」的深度困惑中。

本篇记录真实故障的取证过程与底层机制。

---

## 1. 为什么 Android chroot 必须使用 `unshare -m`

在未隔离的 Android 宿主直接执行 `mount` 会带来严重副作用：
1. **污染全局挂载表**：Android 系统的各种系统服务（如 `vold`、`installd`、`storaged`）会定期扫描全局挂载点。向全局空间注入 Debian 的 `/proc`、`/sys`、`/dev/pts` 等可能干扰宿主服务的正常运作。
2. **卸载残留与设备占用**：如果直接在宿主挂载，当容器内的 shell 意外中断或被 kill 后，挂载点将永久残留，导致后续安装、覆盖或清理时报 `Device or resource busy`。

通过 `/system/bin/unshare -m`（即利用 `unshare(CLONE_NEWNS)` 系统调用），会为当前进程树克隆一份私有的挂载表副本：
* 容器内部进行的所有 `mount` / `umount` 仅在该 Namespace 内部可见，不污染 Android 宿主。
* 当处于该 Namespace 的最后一个进程（通常是 root shell）退出时，内核会自动销毁该 Namespace 并隐式卸载内部所有的挂载点，做到**零残留自动清理**。

### 1.1 关键防泄漏配置：`mount -o rprivate none /`
在克隆出新命名空间后，宿主的根挂载点可能带有 `shared` 挂载传播属性。为了确保容器内的后续所有挂载操作绝对不向宿主或外部扩散，必须在挂载任何新节点前执行：
```bash
/system/bin/mount -o rprivate none /
```
将当前命名空间内的根文件系统及其所有子挂载点递归标记为私有（Private）。

---

## 2. 真实踩坑案例还原

### 2.1 故障演化时序
1. **初始状态**：宿主启动了一个 Debian chroot 会话，并运行了 Antigravity CLI（`agy`）。此时由于启动脚本缺少 `/dev/pts` 挂载，`agy` 在执行 `run_command` 时报错：
   ```text
   failed to create PTY: open /dev/ptmx: no such device
   ```
2. **宿主修复与验证**：用户在 Termux 终端中编辑更新了 `$HOME/.local/bin/debian` 启动脚本，补全了 `mount -t devpts ...`，并在 Termux 中运行 `debian --check`：
   ```text
   UID=0, /proc/self/exe OK, PTY OK
   ```
   自检一次性顺利通过。
3. **奇怪的再次失败**：用户回到运行 `agy` 的交互终端，按下 `Ctrl + C` 中断原有的 `agy` 进程，重新输入：
   ```bash
   agy --dangerously-skip-permissions
   ```
   然而，`agy` 再次尝试派生命令时，**竟然依然抛出完全相同的报错**：
   ```text
   failed to create PTY: open /dev/ptmx: no such device
   ```

---

## 3. 内核取证与根因剖析

为什么明明在新脚本里挂载了 `/dev/pts`，重启的 `agy` 却依旧“看不见”？

通过排查 `/proc` 进程树发现了确凿证据：

### 3.1 进程树分析
```text
[Termux Session]
  └─ /system/bin/unshare -m '$HOME/.local/bin/debian' --root (PID 22643)
      └─ /bin/bash -l (PID 22646)
          └─ agy --dangerously-skip-permissions (PID 20213)  <-- 新拉起的 agy
```

### 3.2 根因定位
1. **Namespace 的单向私有性**：
   Linux 的 Mount Namespace 在执行 `unshare -m` 时，默认建立了私有（Private）隔离。用户在另一个 Termux 终端运行 `debian --check` 时，内核为该检测命令创建了一个**全新的 Namespace B**，并在其中完成了 `/dev/pts` 挂载。
2. **旧终端未完全退出**：
   在正在与 Agent 对话的原终端中，用户虽然杀掉了旧的 `agy`，但**外层的父进程 `/bin/bash -l`（PID 22646）一直在运行**。
3. **命名空间继承**：
   Bash 依然存活在最初建立的**旧 Namespace A（PID 22643）**中。当用户在旧 Bash 里敲下 `agy` 时，新进程继承了父进程的 Mount Namespace A。
4. **挂载表陈旧**：
   检查旧 Namespace 下的 `/proc/mounts`，发现里面依然只有最初挂载的 3 项，根本没有在新脚本中添加的 `/dev/pts`。因此任何在旧 Bash 中启动的程序，无论重启多少次，都绝对无法感知到新挂载点。

---

## 4. Android Toybox 挂载机制的隐形缺陷与绕过

在 Linux 上，我们可以直接使用 `mount --rbind / /android` 将宿主的所有分区递归绑定到目标目录。然而在 Android 宿主上：
* Android 的 `/system/bin/mount` 来自 Toybox/Toolbox，**缺失了 `--rbind`（递归绑定）参数支持**。
* 如果仅执行普通的 `mount / "$ROOT/android"`，只有 Android 的根分区（通常是 erofs 或 ramdisk）被挂载，而挂载在其下的 `/system`、`/vendor`、`/apex`、`/data` 等子文件系统**全部不可见**。

### 4.1 生产级解决方案：动态解析 `/proc/mounts`
在启动脚本中，通过读取当前内核活动挂载表，逐项动态暴露并过滤异常挂载点：

```bash
declare -A SEEN_MOUNTS=()
while IFS=' ' read -r _ target _; do
    case "$target" in
        /|"$ROOT"|"$ROOT"/*|/data/*|/debug_ramdisk/.magisk/preinit|*\\*) continue ;;
    esac
    if [[ ${SEEN_MOUNTS[$target]+yes} ]]; then
        continue
    fi
    SEEN_MOUNTS[$target]=1
    if [[ "$target" == "/data" ]]; then
        destination="$ROOT/android/data"
    else
        destination="$ROOT/android$target"
    fi
    [[ -d "$target" && -d "$destination" ]] || continue
    /system/bin/mount "$target" "$destination" 2>/dev/null || true
done < /proc/mounts
```

* **过滤 `/debug_ramdisk/.magisk/preinit`**：规避 Magisk 早期预初始化节点的内核 `EINVAL` 报错。
* **过滤 `/data/*`**：避免对 `/data` 下的海量应用私有目录进行无意义的重复挂载，只将 `/data` 统一映射至 `$ROOT/android/data`。

---

## 5. 如何准确识别与核验 Namespace 差异

当怀疑多个进程看到的挂载点不一致时，可以通过以下内核接口做绝对比对：

### 5.1 比对 Namespace 节点 inode
每个 Mount Namespace 在 Linux 内核中拥有唯一的 inode 编号。检查 `/proc/<PID>/ns/mnt`：

```bash
# 查看当前 shell 的 Mount Namespace
readlink /proc/$$/ns/mnt
# 输出示例: mnt:[4026533590]

# 查看另一个进程（如宿主或其他终端）的 Mount Namespace
readlink /proc/22643/ns/mnt
# 输出示例: mnt:[4026533512]
```
* **若 inode 编号不同**：说明两个进程位于不同的挂载命名空间，在一个会话里执行的 `mount` 绝不可能同步到另一个会话。

### 5.2 查看特定进程的挂载视图
```bash
# 直接查看目标 PID 进程实际看到的挂载表
cat /proc/<PID>/mountinfo | grep -E '/dev/pts|/proc'
```

---

## 6. 应对与处置军规

1. **改动启动脚本后必须彻底退出（`exit`）**：
   在修改了包含 `unshare -m` 的启动脚本或挂载逻辑后，**切勿只在旧会话中重启上层应用**。必须执行 `exit` 彻底退出内部的 bash，销毁旧 Namespace，退回到宿主 Termux 提示符，再重新调用启动命令。
2. **宿主挂载修复的局限性**：
   在宿主直接针对已存在的 chroot 路径挂载（未带 namespace），由于该容器会话处于独立 namespace，宿主的挂载若在 unshare 之后发生，容器内部通常无法自动继承。
3. **使用 `--check` 进行无侵入验证**：
   在启动器脚本中始终集成 `--check` 模式，在不污染或不打扰交互终端的前提下，单独在干净的命名空间中快速验证挂载与特权矩阵。
