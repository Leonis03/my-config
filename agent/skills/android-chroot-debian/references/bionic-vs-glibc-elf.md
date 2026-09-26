# Android Bionic 与 Linux glibc 冲突：`cannot execute: required file not found` 深度取证

在 Android 设备上的 Termux 终端直接安装或执行标准 Linux CLI 工具（如 Antigravity CLI `agy`、Claude Code、预编译 Go/Rust 二进制）时，最常遭遇的迷惑性报错是：

```text
bash: /data/data/com.termux/files/home/.local/bin/agy: cannot execute: required file not found
```

明明通过 `ls -l` 能清晰看到二进制文件存在、拥有可执行权限（`rwxr-xr-x`），且架构完全匹配（ARM64 / aarch64），为什么系统却坚决坚称「文件未找到」？

本篇记录从底层 ELF 结构与内核 `execve` 机制出发的完整取证过程。

---

## 1. 现场还原与矛盾现象

1. **官方脚本成功安装**：
   在 Termux 中执行安装脚本：
   ```bash
   curl -fsSL https://antigravity.google/cli/install.sh | bash
   ```
   安装器正常检测架构并成功将 `agy` 写入 `$HOME/.local/bin/agy`。
2. **命令执行坚决失败**：
   配置好 `$PATH` 后尝试运行：
   ```bash
   $ agy
   bash: /data/data/com.termux/files/home/.local/bin/agy: cannot execute: required file not found
   ```
3. **初判排查排除常规原因**：
   * 文件存在：`test -f "$HOME/.local/bin/agy"` 返回 0。
   * 权限正确：`chmod +x` 后权限为 755。
   * 不是脚本解释器（Shebang）问题：它是一个 ELF 二进制文件，不是找不到 `#!/bin/bash` 的脚本。

---

## 2. 内核取证：`PT_INTERP` 动态链接器缺失

### 2.1 ELF 结构审查 (`readelf -l`)
使用 GNU binutils 的 `readelf` 检查该二进制的程序头表（Program Headers）：

```bash
readelf -l "$HOME/.local/bin/agy"
```

关键输出片段如下：

```text
Program Headers:
  Type           Offset   VirtAddr           PhysAddr           FileSiz  MemSiz   Flg Align
  ...
  INTERP         0xc615058 0x000000000f215058 0x000000000f215058 0x00001b 0x00001b R   0x1
      [Requesting program interpreter: /lib/ld-linux-aarch64.so.1]
  ...
```

### 2.2 内核 `execve(2)` 的真实执行流
当在终端敲下 `./agy` 时，内核处理动态链接 ELF 的流程为：
1. **读取 ELF 头部**：验证 Magic Number（`7f 45 4c 46`），确认架构为 `AArch64`。
2. **提取动态链接器路径**：解析 `INTERP` 段，获取字符串 `"/lib/ld-linux-aarch64.so.1"`。
3. **加载解释器**：内核尝试在当前 VFS 根目录寻找并打开该路径。
4. **报错触发**：
   * **Android 系统使用的是 Bionic libc**，其 64 位动态链接器路径为 `/system/bin/linker64`（或位于 APEX 运行时的 `/apex/com.android.runtime/bin/linker64`）。
   * 宿主 Android 根文件系统中**根本不存在 `/lib` 目录，更没有 `/lib/ld-linux-aarch64.so.1`**。
   * 内核查找解释器失败，系统调用向 shell 返回 `ENOENT`（No such file or directory）。
5. **Shell 报错信息转换**：
   Bash 收到 `execve` 返回的 `ENOENT` 时，并不会区分是「目标程序自身找不到」还是「目标程序依赖的动态链接器（INTERP）找不到」，统统统一打印为：
   `cannot execute: required file not found`。

---

## 3. 为什么 Termux 无法原生平替 glibc 二进制？

| 维度 | Android 原生环境 (Bionic) | 标准 Linux 发行版 (glibc) |
| :--- | :--- | :--- |
| **C 标准库** | Bionic libc (`libc.so`) | GNU C Library (`glibc` / `libc.so.6`) |
| **动态链接器** | `/system/bin/linker64` | `/lib/ld-linux-aarch64.so.1` |
| **POSIX 支持度** | 轻量化裁剪，缺失许多 GNU 拓展与 IPC 原语 | 完整 POSIX 与 GNU 拓展 |
| **系统调用封装** | 由 Android NDK 严格约束 | 标准 Linux 系统调用封装 |

由于 `agy`、`claude` 等现代智能体与开发者工具链默认基于 glibc 构建，强行用 `patchelf` 修改解释器会遭遇大量的 glibc 符号未定义（如 `glibc_2.34` 等版本符号缺失），稳定性极差。

---

## 4. 解决方案选型：为什么选择 Root chroot Debian？

面对 glibc 依赖，Android 端存在三种主要技术路线：

1. **PRoot / PRoot-distro（用户态模拟）**：
   * **原理**：利用 `ptrace` 拦截所有系统调用，在用户态模拟文件路径重定向与 root 特权。
   * **缺陷**：免 root 但性能损耗大（通常有 20%~40% 的 CPU 开销），对密集型编译、文件扫描（如 Agent 的搜代码、AST 分析）极慢；且经常发生 `ptrace` 死锁或终端挂起。
2. **第三方 patch 包（如 termux-glibc / gcompat）**：
   * **原理**：用垫片库拦截动态调用。
   * **缺陷**：兼容性极脆，遇上复杂的多线程、IPC、Go runtime cgo 时频繁崩溃，无法用于生产级长期开发。
3. **原生 Root chroot（本方案推荐）**：
   * **原理**：利用 Android 宿主已取得的 Root 权限，借助真实 Linux 内核的 `chroot(2)` 切入由 `debootstrap` 构建的原生 Debian/Ubuntu 根文件系统。
   * **优势**：
     * **100% 原生内核执行速度**：零虚拟化开销，直接调度 Android 物理多核 CPU。
     * **真实的 glibc 生态**：拥有标准的 Debian APT 仓库、`/lib/ld-linux-aarch64.so.1` 与完整的 glibc 符号表。
     * **完美的 AI Agent 兼容性**：不仅完美运行 `agy`，还能原生运行 Node.js、Python 3.12+、Rust、Docker CLI 等全套基础设施。
