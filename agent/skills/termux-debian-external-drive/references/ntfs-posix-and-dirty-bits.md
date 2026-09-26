# NTFS POSIX 权限退化与 Windows 脏位（Dirty Bit）排查指南

移动硬盘在跨 Windows 与 Linux / Android 协作时，通常采用 NTFS 或 exFAT 文件系统。虽然两者跨平台兼容性良好，但在用于 Linux 开发、SSH 凭据管理或 Git 仓库托管时，存在严重的语义差异与陷阱。

---

## 1. 踩坑一：NTFS 上的 POSIX 权限伪造与丢失

### 1.1 现象与根因
* **问题**：在挂载的 NTFS 目录上执行 `chmod 600 id_ed25519` 或 `chown root:root file`，命令返回 0（成功），但使用 `ls -la` 查看，权限位依然是固定的（通常是 `770` 或 `755`），用户依然是 `1077` 或 `1000`。
* **根因**：
  * NTFS 本身采用 Windows 安全描述符（SID / ACL），而非标准的 UNIX POSIX uid/gid/mode 体系。
  * Android 的 FUSE 驱动在挂载时使用了固定的模拟映射（例如 `uid=0,gid=1077,fmask=007,dmask=007`）。所有针对文件的底层权限修改在驱动层被丢弃。
* **致命后果**：
  * **OpenSSH 拒绝连接**：OpenSSH 对私钥实施强制安全门禁，若权限不为 `600`，报错：
    ```text
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @         WARNING: UNPROTECTED PRIVATE KEY FILE!          @
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    Permissions 0770 for 'id_ed25519' are too open.
    It is required that your private key files are NOT accessible by others.
    ```
  * **可执行脚本失效**：脚本的 `+x` 标志在拷贝至其他介质时容易失效。

### 1.2 生产级应对方案：归档解压原则
* **严禁将 NTFS 外置盘作为工作区或密钥库直接运行**。
* **归档保护法**：
  * 在打包 SSH 密钥、私有 Git 配置时，使用 `tar` 打包：
    ```bash
    tar -cpf ssh-backup.tar id_ed25519 id_ed25519.pub config known_hosts
    ```
  * `tar` 头部会精确保留原始 Linux `0600`/`0700` POSIX 权限位与用户 ID。
  * 在目标系统的本地 Linux 文件系统（Debian 的 `/root` 或 WSL 的 ext4/f2fs）中解压：
    ```bash
    tar -xpf ssh-backup.tar -C ~/.ssh/
    ```

---

## 2. 踩坑二：Windows 快速启动（Fast Startup）导致的只读（RO）挂载

### 2.1 现象
移动硬盘插入 Android 设备后，在 Debian 中执行写操作（如 `touch test`）报：
```text
touch: cannot touch 'test': Read-only file system
```
查看 `mount | grep media_rw`，参数中包含 `ro` 而非 `rw`。

### 2.2 根因分析
* Windows 默认开启「快速启动」（Fast Startup / 混合休眠）。
* 当 Windows 关机或拔出移动硬盘时，若未完全释放文件系统句柄，NTFS 日志中会打上**脏位（Dirty Bit）**，标记卷处于休眠或不一致状态。
* Linux 内核及 FUSE NTFS 驱动为了保护数据不被破坏，**坚决拒绝以可写模式挂载已休眠的 NTFS 卷**，自动安全降级为只读（Read-Only）。

### 2.3 修复流程
1. **Windows 侧根治**：
   * 必须在 Windows 系统托盘点击「安全删除硬件并弹出媒体」，切勿直接拔线。
   * 彻底禁用快速启动：在管理员 PowerShell 中执行：
     ```powershell
     powercfg /h off
     ```
2. **Debian 应急修复（`ntfsfix`）**：
   如果手头没有 Windows 电脑，且急需在 Debian 中写入，可使用 `ntfsfix` 清理脏卷标记：
   ```bash
   apt install -y ntfs-3g
   # 先卸载已有挂载
   umount /mnt/external
   # 修复脏位日志
   ntfsfix -d /android/dev/block/vold/public:8,97
   # 重新挂载
   mount --bind /android/mnt/media_rw/<UUID> /mnt/external
   ```
