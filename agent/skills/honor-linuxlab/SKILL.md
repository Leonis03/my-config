---
name: honor-linuxlab
description: >-
  Diagnose, recover, and optimize the Honor Tablet Linux Lab (com.hihonor.pcengine) PRoot environment.
  Use when Linux Lab hangs on "Loading..." or black screens during distro switches (Debian xrdb freeze),
  when executing commands inside PRoot without Android root via Intent parameter injection, when safely
  backing up and restoring user data (~/.claude, ~/.gemini, Desktop) before container resets, or when
  purging snapd, configuring APT Pinning (-10 priority), and switching to Tsinghua TUNA ubuntu-ports mirrors.
allowed-tools: Bash Read
---

# 荣耀平板 Linux 实验室运维与排障指南 (Honor Linux Lab)

荣耀平板「Linux 实验室」（`com.hihonor.pcengine`）基于 Android PRoot 用户态虚拟化，为平板提供 Ubuntu 与 Debian 两种桌面环境。宿主无 root 权限，私有目录受 Android 沙箱严格隔离（UID `u0_a303`，700 权限）。

本 skill 汇总多次生产级排障、死锁恢复、无 root 提权注入与系统净化的实战沉淀。

---

## 1. 核心架构认知与安全红线

### 1.1 双系统目录与存储直通
| 组件 | 宿主 Android 路径 | 容器内挂载点 | 说明 |
| :--- | :--- | :--- | :--- |
| **Ubuntu 根文件系统** | `/data/user/0/com.hihonor.pcengine/linuxlab` | `/` | 默认主力系统，Ubuntu 24.04 (Noble)，LXQt + Openbox |
| **Debian 根文件系统** | `/data/user/0/com.hihonor.pcengine/linux` | `/` | 备用系统，Debian 11/12，XFCE4，含未修复启动卡死缺陷 |
| **出厂干净镜像备份** | `/data/user/0/com.hihonor.pcengine/linux_zip/linux_openclaw` | — | 点击「删除桌面数据」时由 `tar -xpmf` 重新解压还原的基底 |
| **外部共享存储** | `/sdcard/` (`/storage/emulated/0`) | `/tablet` 或 `/storage/emulated/0` | **唯一的双向直通数据桥梁**。宿主 shell (UID 2000) 与容器用户 `honor` (UID 1000) 均有完整读写权限 |

### 1.2 绝对安全红线
1. **严禁执行 `pm clear com.hihonor.pcengine`**：会彻底抹掉 App 私有目录及两个 Linux 系统的全量用户数据。
2. **严禁在未备份前点击「删除 Debian/Ubuntu 桌面数据」**：该操作会执行 `rm -rf` 容器目录并从压缩包重新初始化，导致家目录未导出的代码与密钥彻底丢失。
3. **ADB shell（UID 2000）不可直接 `cd` 进入 `/data/user/0/com.hihonor.pcengine/`**：系统报 `Permission denied`，必须通过 `/tablet` 桥接或 Intent 注入通道。

---

## 2. 核心通道：无 Root 容器指令注入 (Intent Injection)

在平板未 Root 且应用为 Release 签名（无法使用 `run-as`）的前提下，利用宿主 `ActivityPcEngine` 对特定 FileProvider URI 解析的漏洞建立代码执行通道。

### 2.1 触发原理
逆向 `ActivityPcEngine.O(Intent)` 与 `f8.b0` 发现：
```java
// 提取 URI 中 /root/ 之后的路径并拼上双引号
if ("com.hihonor.filemanager.share.fileprovider".equals(uri.getAuthority())) {
    String path = uri.getPath().substring(5);
    this.Q = "\"" + path + "\"";
}
// 若以 .deb" 结尾，作为第一条指令写入 PRoot 的标准输入
if (this.Q.endsWith(".deb\"")) {
    firstCommand = "/usr/bin/start " + this.Q + "\n";
}
```

### 2.2 注入执行命令
通过在 URI 中引入双引号截断与 Shell 分号，可直接让容器内 bash 执行放在 `/sdcard`（容器内为 `/tablet`）上的任意脚本：

```bash
# 1. 将目标脚本写入 /sdcard，并赋予执行权限
adb shell "cat << 'EOF' > /sdcard/run_task.sh
#!/bin/bash
exec > /tablet/task_output.log 2>&1
whoami
cat /etc/os-release
EOF
chmod 777 /sdcard/run_task.sh"

# 2. 发送特制 Intent 唤醒执行 (带 StartFinished 信号维持 UI 稳定)
adb shell 'am start -n com.hihonor.pcengine/com.hihonor.hnpcengineclient.pcengine.ActivityPcEngine \
  -d "content://com.hihonor.filemanager.share.fileprovider/root/dummy\" ; sh /tablet/run_task.sh ; echo \"StartFinished\" ; echo \"test.deb\""'

# 3. 检查执行结果
adb shell "cat /sdcard/task_output.log"
```

> 详细逆向分析与冷热启动行为差异见 [references/intent-injection.md](references/intent-injection.md)。也可直接使用工具脚本 [`scripts/run-intent.sh`](scripts/run-intent.sh)。

---

## 3. Debian 桌面卡死在「加载中...」排障与根治

### 3.1 故障现象与根因
* **现象**：从设置切到 Debian 桌面后，界面一直转圈显示「加载中...」，右下角设置齿轮被透明遮罩阻挡无法点击，强杀 App 重启依然卡死。
* **深层根因**：Debian 的启动脚本 `/usr/bin/start` 第 10 行执行了 `xrdb -merge ~/.Xresources`。在 PRoot 虚拟环境下虚拟 X Server（`:99`）未就绪时，`xrdb` 发生底层系统调用死锁，**无超时限制，永久挂起**。脚本永远到不了末尾的 `echo "StartFinished"`，宿主 Java 监听不到该信号，便永久保留加载遮罩。
* **官方对比**：Ubuntu 脚本（`usr/local/bin/start-desktop.sh`）中官方专门封装了 `run_bounded 2s xrdb`，证实此为已知缺陷，但未回滚修复 Debian。

### 3.2 绕过 App 强校验防篡改机制 (`AssetsPatcher`)
直接修改 `/usr/bin/start` 无效：应用类 `AssetsPatcher.kt` 在拉起容器前会对 `usr/bin/start` 计算 SHA256，发现变动立即从 APK 解压覆盖。

**优雅解法：子程序 Wrapper 拦截**
`AssetsPatcher` 只校验 `start`，不校验 `xrdb`。在容器内用 exit 0 脚本替换 `xrdb`：
```bash
# 在容器内执行
sudo cp /usr/bin/xrdb /usr/bin/xrdb.orig
sudo tee /usr/bin/xrdb << 'EOF'
#!/bin/sh
exit 0
EOF
sudo chmod +x /usr/bin/xrdb
```
* 原 `start` 脚本哈希未变，校验通过；
* 执行到 `xrdb` 时瞬间返回 0，3 秒内打出 `StartFinished`，遮罩解除，齿轮恢复。

> 完整复现数据与单步探测过程见 [references/proot-xrdb-analysis.md](references/proot-xrdb-analysis.md)。

---

## 4. Ubuntu 深度净化：彻底去 Snap 与切换清华源

虽然 Ubuntu 在该平板上适配更好（Turnip/Zink 硬件加速可用），但 Canonical 强推的 Snap 在 PRoot 中是无法运行的致命陷阱。

### 4.1 Snap 在 PRoot 中的死穴
* `snapd` 严格需要 Linux 内核 Loop 设备（`/dev/loop*`）、真实 `systemd` PID 1 和 AppArmor；
* Ubuntu 官方源中的 `firefox` 和 `chromium` 只是空壳桩，`apt install` 会暗中触发 `snap install` 导致进程崩溃报错。

### 4.2 净化三步法 (一键执行脚本: [`scripts/setup-nosnap-tuna.sh`](scripts/setup-nosnap-tuna.sh))

#### 1) 彻底卸载 snapd 并清理目录
```bash
sudo apt-get purge -y snapd
sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd /usr/lib/snapd ~/snap /etc/snapd
```

#### 2) APT Pinning 负优先级锁死（永不拉取 Snap）
创建 `/etc/apt/preferences.d/nosnap.pref`：
```ini
Package: snapd
Pin: release a=*
Pin-Priority: -10
```

#### 3) 配置清华大学 TUNA 镜像源（⚠️ 必须使用 ubuntu-ports）
平板架构为 ARM64（`aarch64`），必须使用 `ubuntu-ports/`，使用常规 x86 `ubuntu/` 会报 404：
```bash
sudo tee /etc/apt/sources.list << 'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-security main restricted universe multiverse
EOF
# 禁用 24.04 默认的 deb822 源文件避免冲突
[ -f /etc/apt/sources.list.d/ubuntu.sources ] && sudo mv /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.disabled
sudo apt-get update
```

#### 4) 接入 Mozilla 官方原生 DEB 源（安装真·Firefox）
```bash
sudo install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list
sudo tee /etc/apt/preferences.d/mozilla << 'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF
sudo apt-get update && sudo apt-get install -y firefox firefox-l10n-zh-cn
```

> 注意：卸载 snapd 时若连锁清理了 `pulseaudio`，需立即 `sudo apt install -y pulseaudio` 装回，以保全容器与 Android 宿主之间的音频桥接服务。详见 [references/ubuntu-nosnap-tuna.md](references/ubuntu-nosnap-tuna.md)。

---

## 5. 数据保全与出厂重置标准流程

当 Debian 损坏严重需要重置时，执行如下标准作业流程（SOP）：

```text
[准备阶段] 
  1. 通过 Intent 注入通道将家目录下核心配置打包至 /tablet/ (即宿主 /sdcard/)
     - ~/.claude / ~/.gemini
     - ~/Desktop (排除软链接)
  2. 校验 /sdcard/ 下 tar 包大小与内容完好
       │
[重置阶段]
  3. 点击设置页「删除 Debian 桌面数据」
  4. 系统后台自动执行 tar -xpmf linux_openclaw 恢复纯净出厂系统
       │
[恢复阶段]
  5. 重新切回 Debian 桌面，XFCE 出厂桌面秒级加载
  6. 在终端中一行命令解压还原配置：
     tar -xf /tablet/claude_gemini.tar -C "$HOME"
```
