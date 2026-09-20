# WSL2 图形环境与中文/输入法配置

> **适用环境**：Windows 11 + WSL2 + Ubuntu (22.04 / 24.04 / 26.04) + WSLg
> **适用场景**：在 WSL 中运行 Linux GUI 应用（VS Code / Antigravity IDE 等 Electron 应用、LibreOffice、GIMP、终端），配置中文字体渲染与 Fcitx5 拼音输入法。
>
> 本文由两份文档合并：可复刻的配置指南，以及部署实况与故障记录。2026-09-20 在台式机上逐条复核过，标注含义：
>
> - **【实测 2026-09-20】** —— 这台台式机上当场验证过
> - **【笔记本记录】** —— 来自另一台机器，本机**不复现**，保留是因为换机器可能再遇上

---

## 一、踩坑与根因

### 坑 1：中文字体缺失 / 界面方框乱码

* **根因**：WSL minimal 基础镜像不含 CJK 字体包，中文全被渲染为方框或乱码。
* **解决**：
  1. 安装 Linux 开源中文字体：思源黑体/宋体（`fonts-noto-cjk`）与文泉驿（`fonts-wqy-*`）。
  2. **直通挂载 Windows 宿主机字体**：用 `/etc/fonts/local.conf` 索引 `/mnt/c/Windows/Fonts`，无需复制即可获得微软雅黑、宋体、等线、HarmonyOS Sans 等 1200+ 款字体，**零额外磁盘消耗**。

### 坑 2：Windows 输入法无法在 WSL 窗口中输入中文

* **根因**：WSLg 是基于 RDP 的虚拟化窗口投影，Windows 宿主机输入法（微软拼音/搜狗）只向 Linux 发送原始按键，**不转发候选框与组合事件**（[microsoft/wslg#9](https://github.com/microsoft/wslg/issues/9)）。
* **解决**：在 WSL2 内部独立部署 **Fcitx5** 守护进程与拼音引擎。

### 坑 3：原生 Wayland 下输入法必然断裂，而且会拖垮整个 fcitx5

**【实测 2026-09-20】fcitx5 5.1.7 + 当前 WSLg，逐层验证如下。**

枚举 WSLg 的 Weston 向客户端公布的全局接口（用 `WAYLAND_DEBUG=1` 抓 `wl_registry.global`）：

| 接口 | 公布情况 |
|---|---|
| `zwp_text_input_manager_v1` | ✅ 有 |
| `zwp_text_input_manager_v2` / `v3` | ❌ 未公布 |
| `zwp_input_method_v1` | ✅ 有，**但拒绝绑定** |
| `zwp_input_method_manager_v2` | ❌ 未公布 |

1. Weston 把 `zwp_input_method_v1` 保留给**它自己拉起的** IME 客户端，而 WSLg 不跑那个客户端。第三方输入法一绑就被拒：

   ```
   zwp_input_method_v1@9: error 0: permission to bind input_method denied
   waylandeventreader.cpp:125] Wayland connection got error: 71
   waylandmodule.cpp:351] Connection removed
   ```

2. **后果比"Wayland 输入法不可用"严重得多**：fcitx5 收到 error 71 后会把 `notifications`、`classicui`、`xim`、`dbus` 等**全部 addon 卸载并退出整个进程**。也就是说，不加 `--disable wayland,waylandim` 启动 fcitx5，**连 X11 侧的中文输入都会一起没有**。这条是必需项，不是优化项。

3. Electron 应用跑在原生 Wayland 上时走 `text-input` 协议找输入法，而合成器根本没有输入法可转发 → 打不出中文。**Electron 39 的 `--ozone-platform-hint` 默认值是 `auto`（能 Wayland 就 Wayland）**，所以不显式写 `--ozone-platform=x11` 就会自动掉进这条死路。

* **解决**：fcitx5 用 `--disable wayland,waylandim -d` 启动；GUI 应用显式 `--ozone-platform=x11`。
* 完整验证过程与可复跑的脚本见 [第九节](#九原生-wayland已验证为死路)。

### 坑 4：终端日志刷屏与 Ctrl+C 误杀进程

* **根因**：WSLg 无物理 DRM 设备节点，Chromium/Electron 启动时会输出 `drmGetDevices2() not found` 及 GPU 降级软件渲染警告；若在前台或简单 `&` 启动，日志污染终端，且终端 `Ctrl+C` 会连带杀死 IDE 进程。
* **解决**：用 `setsid` 脱离终端启动并把 stdout/stderr 重定向到 `/dev/null`。

---

## 二、完整复刻步骤

以下步骤可在全新 WSL Ubuntu 上依序执行。

### 步骤 1：安装中文字体与 Windows 宿主机字体映射

```bash
# 1. 安装 Linux 原生开源中文字体包
sudo apt update
sudo apt install -y fonts-noto-cjk fonts-wqy-microhei fonts-wqy-zenhei

# 2. 直通挂载 Windows 宿主机系统与用户字体库（不占 WSL 磁盘，支持更纱黑体等第三方字体）
#
#    用户字体目录的账户名有三种拿法，这里按可靠性排序用前两种：
#      glob          —— 目录已存在时最稳，不依赖任何名字
#      %USERPROFILE% —— 目录还不存在时的权威来源。注意【不要】用 %USERNAME%：
#                       profile 目录名在账户改名后不跟着变，域账户还可能是 user.DOMAIN
#      $USER         —— 错的。Windows 账户名不等于 Linux 用户名；drvfs 大小写不敏感
#                       会让这个错写法在「两者只差大小写」的机器上照样通过，换台机器才炸
#
#    fontconfig 的 <dir> 不支持通配符，所以必须在生成时就解析成实际路径。
WIN_FONTS=$(ls -d /mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts 2>/dev/null | head -1)
if [ -z "$WIN_FONTS" ]; then
  WIN_HOME=$(wslpath -u "$(cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /c 'echo %USERPROFILE%' \
    < /dev/null 2>/dev/null | tr -d '\0\r')")
  WIN_FONTS="$WIN_HOME/AppData/Local/Microsoft/Windows/Fonts"
fi
[ -d "$WIN_FONTS" ] || echo "WARNING: 用户字体目录没解析出来，local.conf 只会有系统字体" >&2

sudo bash -c "cat << EOF > /etc/fonts/local.conf
<?xml version=\"1.0\"?>
<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">
<fontconfig>
    <dir>/mnt/c/Windows/Fonts</dir>
    <dir>${WIN_FONTS}</dir>
</fontconfig>
EOF"

# 3. 刷新字体缓存（全局与当前用户）
sudo fc-cache -f
fc-cache -f

# 4. 生成中英文 UTF-8 语言环境
sudo locale-gen zh_CN.UTF-8 en_US.UTF-8
```

### 步骤 2：安装 Fcitx5 输入法框架与拼音引擎

```bash
sudo apt install -y fcitx5 fcitx5-chinese-addons \
    fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 \
    fcitx5-frontend-qt5 fcitx5-frontend-qt6 \
    fcitx5-config-qt im-config

im-config -n fcitx5
```

### 步骤 3：配置输入法环境变量与默认输入列表

```bash
# 1. 全局环境变量
sudo bash -c 'cat << "EOF" > /etc/profile.d/fcitx5.sh
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=ibus
EOF
chmod +x /etc/profile.d/fcitx5.sh'

# 2. 默认输入法列表（英文键盘 + 拼音）
mkdir -p ~/.config/fcitx5
cat << "EOF" > ~/.config/fcitx5/profile
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=pinyin

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=pinyin
Layout=

[GroupOrder]
0=Default
EOF

# 3. 常用快捷键（Ctrl+Space 与 Left Shift 切换）
cat << "EOF" > ~/.config/fcitx5/config
[Hotkey]
EnumerateWithTriggerKeys=True
EnumerateForwardKeys=
EnumerateBackwardKeys=
EnumerateSkipFirst=False

[Hotkey/TriggerKeys]
0=Control+space
1=Shift_L
2=Shift_R
3=Super+space

[Hotkey/AltTriggerKeys]
0=Shift_L

[Hotkey/PrevPage]
0=Up
1=minus

[Hotkey/NextPage]
0=Down
1=equal
EOF
```

> **`/etc/profile.d/fcitx5.sh` 是全局生效的**，登录 shell（含 zsh，经 `/etc/zsh/zprofile` → `/etc/profile`）都会带上这几个变量。因此**从终端启动的任何 GUI 程序都自动继承**，启动脚本里再 export 一遍是冗余的——只有从应用菜单（`.desktop`）启动时才真正需要，那条路不经过登录 shell。
>
> 老版本文档还让人往 `~/.bashrc` 里追加同样几行。用 zsh 的话那步等于没执行，靠 `/etc/profile.d` 兜住了，可以跳过。

### 步骤 4：部署启动包装器

原件在 [`files/antigravity-ide`](files/antigravity-ide)，部署：

```bash
install -m 755 files/antigravity-ide ~/.local/bin/antigravity-ide
```

它做三件事，每件都有非显然的理由：

| 动作 | 为什么 |
|---|---|
| `fcitx5 --disable wayland,waylandim -d` | 把输入法守护进程拉起来。**`--disable` 是必需的**，否则 error 71 会让 fcitx5 整个退出（坑 3） |
| `--ozone-platform=x11` | Electron 39 默认 `ozone-platform-hint=auto` 会选原生 Wayland，那边输入法不通（坑 3） |
| `setsid` + 重定向 `/dev/null` | 终端脱手、`Ctrl+C` 不误杀、GPU 警告不刷屏（坑 4） |

桌面启动项 `~/.local/share/applications/antigravity-ide.desktop`：

```bash
cat << 'EOF' > ~/.local/share/applications/antigravity-ide.desktop
[Desktop Entry]
Name=Antigravity IDE
Comment=Antigravity IDE (WSLg with Fcitx5 IME)
Exec=$HOME/.local/bin/antigravity-ide %F
Icon=$HOME/opt/antigravity-ide/resources/app/resources/linux/code.png
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=antigravity ide
EOF
```

> 【实测 2026-09-20】`.desktop` 与终端命令是**两条独立入口**，改 `.desktop` 不影响 `antigravity-ide` 命令（后者走 PATH 到 `~/.local/bin/`）。而且本机这个 `.desktop` 建于 `.lnk` 目录最后刷新之后 8 分钟，WSL 一直没重新发布过应用列表，Windows 开始菜单的 `Ubuntu\` 文件夹里**没有**对应的快捷方式——它目前是个死文件，要生效得先 `wsl --shutdown` 让 WSL 重新发布。

---

## 三、验证与排查速查

```bash
# 1. 字体是否生效（能解析出 .ttc / .ttf 路径即可）
fc-match "Noto Sans CJK SC"     # 思源黑体
fc-match "Microsoft YaHei"      # Windows 直通的微软雅黑
fc-match "SimSun"               # Windows 直通的宋体

# 2. Fcitx5 守护进程
ps -ef | grep fcitx5
fcitx5-remote                   # 0=未连接/关闭  1=非激活/英文  2=已激活/中文

# 3. 图形配置面板（词库、模糊音、皮肤）
fcitx5-configtool &

# 4. GUI 应用跑在哪条通道上
xlsclients -l | grep -i <应用名>    # 查得到 = X11/XWayland；查不到 = 原生 Wayland
```

> ⚠️ 用 fcitx5 当探针排查 Wayland 问题时，**必须先 `pkill -x fcitx5`**。已有守护进程会让第二个实例在 0.2 秒内退出，日志只有十几行、根本走不到绑定那一步——「没报错」会被误读成「绑定成功」。

---

## 四、日常使用速查

```bash
# 启动 IDE
antigravity-ide

# 普通 Linux GUI 应用
libreoffice --writer
xterm

# WSLg 重启（在 Windows PowerShell 里执行）
wsl --shutdown
```

* **切换中英文**：编辑器里按 `Ctrl + Space` 或 `Left Shift` 调出拼音候选框。
* **候选词翻页**：`-` / `=` 或方向键。

---

## 五、环境实况

| 项目 | 值 | 来源 |
|---|---|---|
| 发行版 | Ubuntu 24.04.4 LTS（WSL2） | 【实测 2026-09-20】 |
| WSLg | 1.0.73.2（2026-05 构建） | 2026-08-18 记录 |
| **Windows 显示** | **3840x2160，200% 缩放** | 【实测 2026-09-20】weston.log 的 `workArea:(0,0,3840,2064)`，任务栏在 y=2064 |
| WSLg 虚拟屏 | 1920x1080，无缩放（xrandr rdp-0） | 【实测 2026-09-20】 |
| `/etc/wsl.conf` | `systemd=true`、`default=<your-linux-user>`、`interop enabled`、`appendWindowsPath=false` | |
| 显卡 | WSLg 软件渲染回退（GPU 进程初始化失败是正常现象，SwiftShader 兜底） | |

**结论：`appendWindowsPath=false` 与 GUI 显示无关**——WSLg 是独立 VM，不受 PATH 影响。

> 旧版本文档这里写的是「Windows 显示 1920x1080 @ 100% 缩放」，那是【笔记本记录】。本机是 4K + 200% 整数缩放，WSLg 拿到的是 1920x1080 的逻辑分辨率。**这个差异可能正是第八节点击偏移只在笔记本出现的原因**——坐标偏移对缩放比极其敏感，非整数缩放（125% / 150%）叠加装饰框最容易出问题。

---

## 六、WSLg 运行期故障与修复

### 6.1 窗口只出现在任务栏、无画面【笔记本记录】

* **症状**：任务栏有进程条目（RAIL 通道通），但窗口画面不显示；连 `xterm` 也一样。
* **排查**：X 侧完全正常（窗口已映射、Viewable、位置正确）；Weston 无错误；RDP 连接活着。
* **根因**：WSLg 的 RDP 渲染层卡死（日志中 `peer_recv_pdu() fail` 掉线重连后状态未完全恢复）。
* **修复**：Windows PowerShell 执行 `wsl --shutdown`，重启 WSLg 后恢复。
* **预防**：再出现先试 `wsl --shutdown`；仍不行则管理员 PowerShell `wsl --update`。

### 6.2 LibreOffice 窗口不显示

与 6.1 同一根因，**不是 LibreOffice 的问题**。`SAL_USE_VCLPLUGIN=gen` 后端在 WSLg 下更稳，但 WSLg 修好后默认后端也可用。

### 6.3 xterm 字体报错（小瑕疵）

`cannot load font "-misc-fixed-...-iso10646-1"` → `sudo apt install xfonts-base`，或 `xterm -fa 'DejaVu Sans Mono'`。

---

## 七、Antigravity IDE 部署

| 项目 | 值 |
|---|---|
| 版本 | 1.107.0 · commit `ecfbad74d93962fc8ca485d93ab9b4f3d4cb6cf8` · quality stable · 构建 2026-08-13T08:37:22Z |
| Electron | 39.2.3（运行期由 crashpad 的 `--annotation=ver=` 带出，离线包里读不到） |
| 安装位置 | `~/opt/antigravity-ide/`，主二进制 `antigravity-ide` 约 199 MB |
| 厂商 CLI 入口 | `~/opt/antigravity-ide/bin/antigravity-ide`（VS Code 标准 shim，带 WSL 检测提示，需 `DONT_PROMPT_WSL_INSTALL=1` 跳过） |
| 补充依赖 | `libasound2`、`libxss1` |
| 沙箱 | Ubuntu 默认 user namespace 即可，无需 setuid chrome-sandbox |
| 配置目录 | `~/.config/Antigravity IDE/` |

### 跑「原装、未配置」的版本

排查时经常需要绕开包装脚本：

```bash
# 厂商 CLI 入口（会提示请在 Windows 侧安装，故需要那个环境变量）
DONT_PROMPT_WSL_INSTALL=1 ~/opt/antigravity-ide/bin/antigravity-ide

# 直接调 Electron 主二进制，连 CLI shim 都跳过
DONT_PROMPT_WSL_INSTALL=1 ~/opt/antigravity-ide/antigravity-ide
```

裸跑相对包装脚本少四样：不拉起 fcitx5；无 `--ozone-platform=x11`（于是走 Wayland，中文打不出）；前台运行被警告刷屏且 `Ctrl+C` 连带杀进程；无窗口化处理。

> ⚠️ **`--user-data-dir` 决定登录态**。Google 登录信息存在 user-data-dir 里，换一个目录或删掉它就要重新登录一次。排查时固定用同一个测试 profile（例如 `~/.cache/antigravity-smoke`），别每次新建，也别放 `/tmp`（重启即失）。
>
> 同一个 user-data-dir 不能同时跑两个实例——第二次启动只会把已有窗口拉到前台。所以测试用的 profile 要和日常用的分开。

---

## 八、最大化时点击偏移【笔记本记录，本机不复现】

### 症状规律（笔记本）

| 窗口状态 | 点击准确性 |
|---|---|
| 正常窗口化（小窗口） | ✅ 准确 |
| 最大化 | ❌ 偏移（窗口几何错乱，内容按错误尺寸渲染） |
| F11 全屏 | ✅ 准确 |

### 根因（笔记本）

WSLg 已知 bug：**最大化窗口 + 装饰框（27px 原生标题栏）导致输入坐标偏移**，且最大化时窗口几何计算错误。

* [microsoft/wslg#1015](https://github.com/microsoft/wslg/issues/1015)：Borderless Maximized 窗口不填满工作区且点击偏移
* [JetBrains JBR-6223](https://youtrack.jetbrains.com/projects/JBR/issues/JBR-6223)：最大化窗口从 0,0 向右下偏移

`_MOTIF_WM_HINTS` 去装饰在 Weston 下无效；`--force-device-scale-factor=1` 无益。

### 本机为何判定为不复现

【实测 2026-09-20】时间线本身就说明这份记录不是在本机做的：

```
IDE 二进制时间戳        2026-08-13 16:54    （与厂商包构建同日，可能随包带来）
本节原始记录落款        2026-08-18          ← 在中间
本机首次真正运行        2026-08-23 20:04    ← ~/.config/Antigravity IDE/Crashpad/client_id，首启才生成
启动脚本写成            2026-08-25 11:48
```

实测复核：X11 通道下把窗口最大化（`xwininfo` 实测几何 `1920x1032+32+32`）点击准确；原生 Wayland 通道下同样准确。两条通道都不复现。

### ⚠️ 那个「窗口化修复脚本」在 WSLg 上根本跑不通

原记录给的修复是一个 `antigravity-ide-windowed` 包装脚本：启动后轮询找窗口，再用 `wmctrl` 解除最大化并 resize。**【实测 2026-09-20】这个方案在 WSLg 下不可能生效**：

```
$ wmctrl -l
Cannot get client list properties.
(_NET_CLIENT_LIST or _WIN_CLIENT_LIST)          exit=1

$ wmctrl -m
Name: Weston WM
```

WSLg 的 Weston WM **不导出 `_NET_CLIENT_LIST`**，`wmctrl -l` 永远失败。而脚本找窗口只有这一句：

```bash
WID=$(wmctrl -l 2>/dev/null | grep -i "Antigravity IDE" | awk '{print $1}' | head -n 1)
```

实测返回空 → 循环空转 40 次（20 秒）后静默放弃，`wmctrl -i -r ... remove,maximized` 一次都执行不到。同理，原文给的两条手动恢复命令也执行不了。

窗口本身是好的，`xwininfo -root -tree` 一眼就能找到——不是窗口的问题，是 `wmctrl` 依赖的 EWMH 属性 Weston 不提供。原记录自己的待办里写着「包装脚本尚未端到端实测」，现在知道了：**实测也不会通过**。

要在 WSLg 上做窗口摆放，得换用 `xdotool`（走 X 协议直接操作窗口，不依赖 `_NET_CLIENT_LIST`），或直接读 `xwininfo -root -tree` 拿窗口 ID。本机因为不复现偏移，没有做这件事的必要，故该脚本未收入仓库。

---

## 九、原生 Wayland：已验证为死路

原记录留过一条待办——「尝试 Wayland 原生模式，WSLg 的 Wayland 路径无 XWayland 装饰框偏移，可能让最大化/拖拽也正常」。**【实测 2026-09-20】结案为否。**

### 验证脚本

[`wayland-ime-smoke.sh`](wayland-ime-smoke.sh) 把三个互相独立的失败点分段测，避免把结论归错因：

```bash
bash wsl/gui-ime/wayland-ime-smoke.sh        # 用 text-input-v1（本机唯一被公布的版本）
bash wsl/gui-ime/wayland-ime-smoke.sh 3      # 强行试 v3，复核「没公布就是不行」
FRESH=1 bash wsl/gui-ime/wayland-ime-smoke.sh   # 清空测试 profile（会需要重新登录）
```

它会：枚举合成器公布的接口 → 测 fcitx5 能否绑定 `input_method` → 用最优参数（`--enable-wayland-ime --wayland-text-input-version=1`、`XCURSOR_SIZE=24`、全套 IM 环境变量）开一个原生 Wayland 窗口 → 停下来等人工实测打字 → 给判决。跑完会把 fcitx5 恢复成 X11 模式。

### 实测结果

```
1. 合成器      ✓ zwp_text_input_manager_v1      ✗ v2 / v3 未公布
               ✓ zwp_input_method_v1            ✗ input_method_manager_v2 未公布
2. 输入法侧    ✗ Weston 拒绝绑定 input_method（error 71），fcitx5 整个进程退出
3. 应用侧      ✓ Electron 拿到了 zwp_text_input_manager_v1
               ✗ 但从未发出 text_input 请求
4. 人工        ✗ 窗口里打不出中文
```

**链路断在「合成器 ↔ 输入法」之间**：应用就算申请了输入法，Weston 也没有输入法可以转发。这不是配置问题，参数调到最优也没用。

两个顺带的结论：

* 网上通行的 `--wayland-text-input-version=3` 在 WSLg 上**必然无效**，因为 Weston 压根没公布 v3。要试只能试 v1。
* 换 Wayland 一无所得：本机最大化本来就不偏（第八节），光标还会变得过大（`XCURSOR_SIZE` 未设时按输出缩放放大，4K/200% 下翻倍，需 `XCURSOR_SIZE=24` 才正常）。

**所以：留在 `--ozone-platform=x11`。**

---

## 十、日志噪音对照

WSLg 下启动 Electron 应用必然刷一屏红字，绝大部分可以忽略：

| 日志 | 定性 |
|---|---|
| `Exiting GPU process due to errors during initialization` ×5–7 | **正常**。无 DRM 设备，GPU 进程起不来 → 回退 SwiftShader 软件渲染 |
| `drmGetDevices2() has not found any devices` | 同上，Wayland 通道下报在 `ui/ozone/platform/wayland/...` |
| `Creation of StagingBuffer's SharedImage failed` ×12 | 同上的下游表现 |
| `Automatic fallback to software WebGL has been deprecated` | 提示性，不影响编辑器本身 |
| `libnotify / org.freedesktop.Notifications not provided` | WSL 里没有桌面通知守护进程，通知发不出去，无害 |
| `fileWatcher crashed with code 5` | **不是噪音**，四轮启动全部复现，是稳定的文件监视器崩溃，待查 |

拖动卡顿（「眨眼补帧」）就是软件渲染的代价，与点击偏移无关。想省掉 GPU 进程反复崩溃可以加 `--disable-gpu`，但渲染仍是软件的。

---

## 十一、待办

- [ ] **`fileWatcher crashed with code 5`**：四轮启动稳定复现，尚未排查。
- [ ] **应用菜单入口**：`.desktop` 未被 WSL 发布成 Windows 开始菜单快捷方式（见步骤 4 注）。要么 `wsl --shutdown` 触发重新发布，要么确认不需要这个入口。
- [ ] **xterm 字体**：`sudo apt install xfonts-base`。
- [x] ~~尝试 Wayland 原生模式~~ —— 2026-09-20 结案为否，见第九节。
- [x] ~~验证窗口化包装脚本冷启动~~ —— 2026-09-20 查明其依赖的 `wmctrl` 在 WSLg 不可用，见第八节。

---

## 十二、相关文件清单

| 文件 | 说明 |
|---|---|
| `~/opt/antigravity-ide/` | IDE 本体 |
| `~/.local/bin/antigravity-ide` | 启动包装器，原件见 [`files/antigravity-ide`](files/antigravity-ide) |
| `~/.local/share/applications/antigravity-ide.desktop` | 应用菜单启动项（当前未被 WSL 发布，见步骤 4 注） |
| `~/.config/Antigravity IDE/` | IDE 用户配置与登录态 |
| `~/.cache/antigravity-smoke/` | 排查用的独立测试 profile（由 smoke 脚本创建） |
| `/etc/fonts/local.conf` | Windows 字体直通配置 |
| `/etc/profile.d/fcitx5.sh` | 输入法全局环境变量 |
| `~/.config/fcitx5/profile`、`~/.config/fcitx5/config` | 输入法列表与快捷键 |

原记录里的 `$HOME/code/gui/Antigravity IDE.tar.gz`（230 MB 安装包）**已不在本机**，目录都不存在了。
