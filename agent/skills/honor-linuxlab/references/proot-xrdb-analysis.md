# 荣耀平板 Linux 实验室 Debian 卡死深度剖析与 AssetsPatcher 绕过

## 1. 卡死现象复现与抓包取证

当用户在荣耀平板设置中点击「切换至 Debian 桌面」后，Android Activity `ActivityPcEngine` 进入全屏展示。界面中央渲染半透明蒙层并不断旋转显示「加载中...」，右下角的齿轮设置菜单被阻挡。

### 1.1 进程树与阻塞点快照
通过 `adb shell ps -ef` 观察容器内进程状态：
```text
u0_a303   proot -0 --bind=... --rootfs=/data/user/0/com.hihonor.pcengine/linux /usr/bin/env ...
u0_a303    \_ bash /usr/bin/start 0 3000x1920 /usr/local/bin/pkg_monitor.sh
u0_a303        \_ Xvfb :99 -screen 0 3000x1920x24 -fbdir /home/XvfbScreen -dpi 192
u0_a303        \_ pulseaudio --exit-idle-time=-1 --disable-shm --start
u0_a303        \_ xrdb -merge ~/.Xresources <--- [永久阻塞挂死]
```

### 1.2 启动脚本 `/usr/bin/start` 源码
```bash
#!/bin/bash
if [ "$1" = "0" ];then
    echo "Start software: $3"
    rm -rf /tmp/.*X99-lock*
    eval `dbus-launch --auto-syntax`
    Xvfb :99 -screen 0 $2x24 -fbdir /home/XvfbScreen -dpi 192 &
    pulseaudio --exit-idle-time=-1 --disable-shm --start
    xrdb -merge ~/.Xresources
    fcitx5 &
    xfce4-session &
    sleep 3
    $3 &
    echo "StartFinished"
fi
```

### 1.3 核心机制断裂点
1. **`xrdb` 系统调用死锁**：在 PRoot 环境中，`Xvfb` 后台启动后未建立好 socket 监听，或 DISPLAY 环境变量与 UNIX domain socket 权限不匹配时，`xrdb` 进入无超时阻塞，进程永远卡在第 10 行。实测通过 Coreutils timeout 测试：
   `timeout 3 xrdb -merge ~/.Xresources` 必返回退出码 `124`。
2. **握手信号断裂**：宿主 Java 类 `f8.r0` 启动工作线程监听容器的 stdout，阻塞等待 `"StartFinished"` 字符串。因脚本停在第 10 行，第 15 行的 `echo "StartFinished"` 永远无法发出。宿主接收不到信号，遮罩永不淡出。

---

## 2. 官方防篡改校验机制：`AssetsPatcher`

试图直接修改容器文件系统里的 `/usr/bin/start`（例如加上超时或注释掉 `xrdb`）会遇到二次陷阱：

逆向 `com.hihonor.pcengine` 的 `z4.d`（`AssetsPatcher.kt`）：
```kotlin
// 启动前计算目标文件 SHA256
val targetFile = File(rootfs, "usr/bin/start")
val currentHash = Sha256.digest(targetFile)
val expectedHash = "22b718f3db8671c55d819baa358aa0f4ca89ad7b9db3d72c718aca247bbebc91"

if (currentHash != expectedHash) {
    // 发现哈希不匹配，强行从 APK assets/start_patch/start 覆盖还原！
    copyAssetToFile("start_patch/start", targetFile)
}
```
**后果**：每次强杀重启应用，`AssetsPatcher` 会检测到哈希不符，立即重新写回那个只有 388 字节的带 Bug 原始脚本。

---

## 3. 双层绕过解决方案：子程序 Wrapper

通过全面反编译审计 `AssetsPatcher.kt` 的文件监控列表，发现应用仅监控了 8 个特定补丁资产：
* `assets/start_patch/start` -> `usr/bin/start`
* `assets/start_patch/start-desktop` -> `usr/local/bin/start-desktop.sh`
* `assets/xvfb_patch/Xvfb` -> `usr/bin/Xvfb`
* `libFcitx5Core.so` 等

**关键破局点**：`AssetsPatcher` **完全没有监控 `/usr/bin/xrdb` 和 `/usr/bin/pulseaudio`**！

### 落地操作
保留原始 `/usr/bin/start` 不动（其 SHA256 依然完全符合官方预期），直接替换其调用的子命令：

```bash
# 备份原二进制文件
cp /usr/bin/xrdb /usr/bin/xrdb.real

# 写入即时返回 0 的 shell 桩脚本
cat << 'EOF' > /usr/bin/xrdb
#!/bin/sh
exit 0
EOF
chmod +x /usr/bin/xrdb
```

### 执行收益
1. `AssetsPatcher` 校验 `/usr/bin/start`，哈希完全匹配，跳过覆写。
2. 容器执行 `start` 脚本，运行到 `xrdb` 时瞬间返回 0。
3. 脚本在 3 秒后打印出 `StartFinished`。
4. 宿主 `f8.r0` 收到信号，立即调度移除 Loading 遮罩，右下角齿轮成功激活。
