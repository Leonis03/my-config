# 荣耀平板 Linux 实验室 Ubuntu 去 Snap 与清华源配置细节

## 1. PRoot 环境与 Snap 的架构冲突

荣耀平板「Linux 实验室」最新版本运行的是 **Ubuntu 24.04 LTS (Noble Numbat)** 的 ARM64 架构镜像。虽然官方为其配置了 Zink/Turnip 图形硬件加速以及 LXQt 桌面，但保留了 Canonical 默认的 Snap 体系。

### 为什么 Snap 必定在 PRoot 失败？
* **Loop 设备缺失**：Snap 将软件包挂载为 SquashFS 只读环回文件系统（`/dev/loop*`）。Android 内核出于安全沙箱隔离，禁止非 Root 进程调用 `ioctl(LOOP_SET_FD)`，因此容器内无法挂载 snap 镜像。
* **无真实 Systemd**：Snap 强依赖 systemd 作为 PID 1 来管理 sockets 和 services。PRoot 只是 ptrace 系统调用截获模拟，荣耀在内部使用 `linuxlab-systemd-compat` 垫片脚本处理基础服务，但无法支撑复杂的 snapd cgroups 和 systemd-units。
* **AppArmor 限制**：Snapd 在启动应用时要求 Linux 内核级 AppArmor 策略支持，Android 内核只使用 SELinux，导致权限校验直接阻断。

---

## 2. 深度清除与 APT 永久锁死策略 (APT Pinning)

### 2.1 卸载 Snapd 与清理磁盘残留
```bash
sudo apt-get purge -y snapd
sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd /usr/lib/snapd ~/snap /etc/snapd
```

### 2.2 APT Pinning 负优先级机制
在 Ubuntu 体系中，即便删除了 `snapd`，某些带有 `Recommends: snapd` 的软件包在执行 `apt install` 或 `apt upgrade` 时仍会试图偷偷拉回 `snapd`。

Debian/Ubuntu 官方提供了 **APT Pinning 机制**。在 `/etc/apt/preferences.d/nosnap.pref` 中配置负优先级：
```ini
Package: snapd
Pin: release a=*
Pin-Priority: -10
```

* **优先级含义**：
  * `Pin-Priority < 0`：APT 绝对不会安装该软件包。
  * 效果：运行 `apt-cache policy snapd` 时，候选版本显示为 `(无)`（None）。系统对任何形式的 Snap 依赖实现永久免疫。

---

## 3. 清华大学 TUNA 镜像站配置 (ARM64 架构避坑)

### 3.1 致命架构陷阱：`ubuntu` vs `ubuntu-ports`
* **x86_64 电脑**：Ubuntu 软件源目录为 `https://mirrors.tuna.tsinghua.edu.cn/ubuntu/`
* **ARM64 平板**：Ubuntu 官方及其镜像站将非 x86 架构单独分流到了 **`ubuntu-ports/`** 目录！
* 如果将 PC 上的换源教程直接搬到平板上（即配置了 `/ubuntu/`），执行 `sudo apt update` 时会全部报出 `404 Not Found`，提示找不到 `binary-arm64/Packages`。

### 3.2 针对 Ubuntu 24.04 (Noble) 的标准配置
清华源配置写入 `/etc/apt/sources.list`：
```text
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-security main restricted universe multiverse
```

* **Ubuntu 24.04 deb822 处理**：Ubuntu 24.04 默认推荐使用 `/etc/apt/sources.list.d/ubuntu.sources`。为防止软件源重复引发 APT 警告，需将默认的 `ubuntu.sources` 重命名禁用：
  ```bash
  [ -f /etc/apt/sources.list.d/ubuntu.sources ] && sudo mv /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.disabled
  ```

---

## 4. Mozilla 官方原生 DEB 软件源集成

Ubuntu 官方仓库中的 `firefox` 和 `chromium-browser` 已转为 Snap 引导包（Transitional Dummy Package），如果直接 `apt install firefox` 会触发 Snap 错误。

### 接入 Mozilla 官方原生源
Mozilla 团队为 Debian/Ubuntu 提供了一级公民的原生 APT 仓库：

```bash
# 1. 创建密钥存储目录
sudo install -d -m 0755 /etc/apt/keyrings

# 2. 获取 Mozilla 官方签名公钥
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null

# 3. 添加软件源
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list

# 4. 配置优先级，确保优先于 Ubuntu 官方的 Snap 假包
sudo tee /etc/apt/preferences.d/mozilla << 'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

# 5. 更新并安装原生 Firefox
sudo apt-get update
sudo apt-get install -y firefox firefox-l10n-zh-cn
```

---

## 5. 音频组件防护与恢复

在执行 `apt purge snapd` 或 `apt autoremove` 时，某些桌面音频包（如 `pavucontrol-qt`）可能会因为间接依赖变化导致 `pulseaudio` 被联动移除。

* **重要校验**：卸载完成后务必检查 `which pulseaudio`；
* **修复方法**：若 `pulseaudio` 缺失，执行 `sudo apt-get install -y pulseaudio` 即可。由于已配置 `snapd` 负优先级，重装 PulseAudio 绝不会重新引入 snapd。
