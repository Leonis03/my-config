# pnpm / npm 双端空间清理指南（pnpm 12 时代）

> 版本：2026-09-20 重写。取代 `pnpm-npm-cleanup-20260916.md`（那一版针对 pnpm ≤10 的 `global/5` 布局，WSL 侧已失效）。
>
> 适用范围：WSL (Ubuntu) + Windows 两侧的 pnpm / npm，以及通过 pnpm 全局安装的 Claude Code、Codex 等 CLI。
>
> **两侧现在版本不同，流程也不同**，不要互抄：
>
> | | pnpm | 全局布局 | 本文对应章节 |
> |---|---|---|---|
> | WSL | 12.5.1 | `~/.local/share/pnpm/global/v11/<hash>/` | §3（几乎不用管） |
> | Windows | ≤10 | `%LOCALAPPDATA%\pnpm\global\5\.pnpm\` | §4（仍需手动清） |

---

## 1. 先记住一条方法论：`du` 会重复计算硬链接

pnpm 的全局目录和 node_modules 里的文件，都是 store 内容的**硬链接**。对两个目录分别 `du -sh`，同一份数据会被数两遍；把这些数字相加当成"可释放空间"，结果必然虚高。

本机实测（清理前）：

```
单独测：global/5 = 1.1G    store/v10 = 4.0G
合并测：global/5 = 1.1G    store/v10 = 2.9G    ← 凭空少了 1.1G
去重总计（du -csh 两者）= 4.0G
```

抽查 `global/5/.pnpm/@openai+codex@0.143.0/.../codex.js`，`links=3`。也就是说 **`global/5` 那 1.1 GB 全部是 `store/v10` 内容的硬链接，单独删掉它一个字节都释放不了**。

由此得到两条规则：

1. 估算可释放空间用 `du -csh A B C` 的**去重总计**，不要把单独测的数字相加。
2. 最终以清理前后 `df -h /` 的实际变化为准。
3. 删全局目录本身不释放空间，它的作用是**让 store 里的内容变成孤儿，从而可以被 `pnpm store prune` 回收**。收益来自 store，不来自全局目录。

---

## 2. 本次清理实测记录（2026-09-20，WSL 侧）

执行的命令：

```bash
rm -rf ~/.local/share/pnpm/global/5 ~/.local/share/pnpm/store/v10 \
       ~/.cache/pnpm ~/.cache/node/corepack ~/.npm/_npx
npm cache clean --force
pnpm store prune -y
```

结果：

| 目标 | 清理前 | 清理后 | 说明 |
|---|---:|---:|---|
| `global/5` + `store/v10`（去重） | 4.0 G | 0 | pnpm ≤10 的遗留，11/12 完全不读 |
| `~/.npm`（`_cacache` 643 M + `_npx` 48 M） | 690 M | 172 K | 本机 npm 全局只有 npm + corepack |
| `~/.cache/pnpm` | 367 M | 0 | registry metadata，会自动重建 |
| `~/.cache/node/corepack` | 109 M | 0 | corepack 未启用 |
| `store/v11`（`pnpm store prune`） | 6.5 G | 6.3 G | 清掉 43 个无引用包 |
| `global/v11` | 2.0 M | 2.0 M | 现役全局目录，本来就极小 |

`df -h /`：**已用 58 G → 52 G，净释放约 6 GB**。

清理后验证全部通过：

```
node v24.21.0   npm 11.19.0   pnpm 12.5.1
claude 2.1.278  codex-cli 0.155.1  opencode 1.18.31  ccstatusline 2.2.29
pnpm ls -g → 7 个包全在
```

唯一代价：日后若通过 corepack 或 `pnx pnpm@10` 运行老版本 pnpm，需要重新下载一份 store。

---

## 3. WSL（pnpm 11+）：日常几乎不用清

### 3.1 为什么不用清了

pnpm 11.0 改了全局安装布局：以前所有全局包挤在一个项目里（`global/5`），现在**每个 `pnpm add -g` 一个独立目录**，各自带 `package.json`、`node_modules`、lockfile，路径是 `{PNPM_HOME}/global/v11/<hash>/`。

这个 `v11` 是**布局格式版本号，不跟 pnpm 主版本走**——pnpm 12 没改布局，所以继续写进 `v11`。对比 `global/5` 被 pnpm 7–10 共用了四个大版本就清楚了。

关键变化：**旧版本不再堆积**。本机实测 7 个全局包 ↔ `global/v11` 下 7 个真实目录，严格 1:1；升级 pnpm 自身时，被取代的旧安装组会在下一次 `pnpm add -g` 时被自动回收。整个 `global/v11` 只有 2.0 MB。

所以旧指南"手动辨认并删除全局虚拟 store 里的旧版本目录"那套流程，在 pnpm 11+ 上**既无对象、也无必要**。

### 3.2 日常维护（全部内容）

```bash
cd ~                       # 见 §3.4，别在 /mnt/c 下跑
pnpm store prune -y        # 唯一需要定期做的事
```

可选、按需：

```bash
rm -rf ~/.cache/pnpm       # registry metadata，会重建
npm cache clean --force    # 若仍在用 npm/npx
rm -rf ~/.npm/_npx
```

#### 升级全局包时会被 postinstall 拦住

pnpm 10 起默认**不执行**依赖的生命周期脚本（`postinstall` 等），这是为了防供应链攻击。代价是某些包装不全——Claude Code 的 `postinstall` 要下原生组件，被拦掉后命令能装上却跑不起来。

```bash
pnpm update -g --latest                                          # 会被静默拦住
pnpm update -g --latest --allow-build=@anthropic-ai/claude-code  # 显式放行
```

`--allow-build` 按**包名**放行，是白名单不是开关，所以不会把其它依赖的脚本一起放开。要长期生效可以写进 `package.json` 的 `pnpm.onlyBuiltDependencies`，全局包的场景直接带参数更省事。

坑在于**它不报错**：`pnpm` 只在输出里提一句 build 被忽略，退出码 0，看起来装成功了。故障要等到真正运行那个命令时才出现。本机 pnpm 11.27.0 仍是这个行为。

### 3.3 一次性遗留清理（换机器 / 首次执行时用）

只在还残留 pnpm ≤10 时代目录的机器上需要。先确认现役路径，再删：

```bash
pnpm store path            # 应输出 .../store/v11
pnpm root -g               # 应输出 .../global/v11

# 确认 global/5 已无引用
grep -l 'global/5' ~/.local/share/pnpm/bin/* 2>/dev/null || echo "无引用，可删"

du -csh ~/.local/share/pnpm/global/5 ~/.local/share/pnpm/store/v10   # 去重总计
rm -rf ~/.local/share/pnpm/global/5 ~/.local/share/pnpm/store/v10
```

### 3.4 WSL 专属坑：先 `cd ~`

如果当前目录停在 `/mnt/c`，某些 pnpm 操作会尝试在当前目录创建临时探测文件；若 C 盘挂载为只读，会报 `EROFS: read-only file system`。切回 Linux 侧目录即可避免。

非交互 shell 里如需 nvm：

```bash
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
```

> 注意：pnpm 12 是原生二进制，**自身不再依赖 Node**，上面这行只对通过 pnpm 全局安装的 JS CLI（claude / codex 等）有意义。

### 3.5 验证

```bash
pnpm -v && pnpm ls -g
claude --version; codex --version
```

全局 bin 在 `~/.local/share/pnpm/bin/`（pnpm 11 起从 `PNPM_HOME` 根目录移进了 `bin/` 子目录，旧文档里的 `~/.local/share/pnpm/claude` 路径已失效）。

---

## 4. Windows（pnpm ≤10）：旧流程仍然有效

> **作废条件**：若 `%LOCALAPPDATA%\pnpm\global\` 下出现 `v11` 目录，说明 Windows 侧也升到 pnpm 11+ 了，**本节整节作废**，改用 §3。

本机 Windows 侧实测仍是 `global\5` 布局，且确实在堆版本：

```
@anthropic-ai+claude-code@2.1.270      ← 旧
@anthropic-ai+claude-code@2.1.278      ← 当前
@openai+codex@0.153.4                  ← 旧
@openai+codex@0.154.0                  ← 旧
@openai+codex@0.155.1                  ← 当前
（含各自的 -win32-x64 平台包）
```

### 4.1 顺序

1. 确认当前版本 → 2. 删全局虚拟 store 里的旧版本目录 → 3. `pnpm store prune` → 4. 可选清 corepack / npm 缓存 → 5. 验证。

顺序不能反：先 prune 的话，旧目录仍持有引用，store 清不干净。

### 4.2 查看

```powershell
pnpm ls -g
pnpm store path
npm config get cache
npm ls -g --depth=0

$base = Join-Path $env:LOCALAPPDATA "pnpm\global\5\.pnpm"
Get-ChildItem $base -Directory |
  Where-Object { $_.Name -match 'claude-code|codex' } |
  Select-Object -ExpandProperty Name
```

### 4.3 删除旧版本 + prune

必须保留：`pnpm ls -g` 显示的当前版本、其对应平台包目录、`.pnpm` 下的 `node_modules` 等非版本目录、任何用途不明的目录。

```powershell
$base = Join-Path $env:LOCALAPPDATA "pnpm\global\5\.pnpm"
$orphans = @(
  "@anthropic-ai+claude-code@旧版本号",
  "@anthropic-ai+claude-code-win32-x64@旧版本号",
  "@openai+codex@旧版本号",
  "@openai+codex@旧版本号-win32-x64"
)
foreach ($o in $orphans) {
  $p = Join-Path $base $o
  if (Test-Path $p) { Remove-Item $p -Recurse -Force; "deleted: $o" }
}

pnpm store prune
```

### 4.4 缓存

```powershell
corepack cache clean          # 可选，全清；下次用 corepack 的 pnpm 会自动重下

npm cache clean --force       # `using --force Recommended protections disabled` 是正常提示
$npmCache = npm config get cache
$npxCache = Join-Path $npmCache "_npx"
if (Test-Path $npxCache) { Remove-Item $npxCache -Recurse -Force }
```

### 4.5 npm → pnpm 迁移残留

```powershell
npm ls -g --depth=0
# 确认不再使用后再卸载
npm uninstall -g @anthropic-ai/claude-code
npm uninstall -g @openai/codex
```

### 4.6 验证

```powershell
claude --version; codex --version; pnpm --version; pnpm ls -g
```

---

## 5. Windows 维护脚本（预览优先）

保存为 `cleanup-pnpm.ps1`。默认只**预览**，加 `-Apply` 才真删。开头带 §4 的作废检查。

```powershell
param(
  [Parameter(Mandatory=$true)][string]$ClaudeVersion,
  [Parameter(Mandatory=$true)][string]$CodexVersion,
  [switch]$Apply,
  [switch]$CleanCorepack,
  [switch]$CleanNpmCache
)

$globalRoot = Join-Path $env:LOCALAPPDATA "pnpm\global"
if (Test-Path (Join-Path $globalRoot "v11")) {
  throw "检测到 global\v11：Windows 侧已升级到 pnpm 11+，本脚本作废，改用新版流程（指南 §3）。"
}

$base = Join-Path $globalRoot "5\.pnpm"
if (!(Test-Path $base)) { throw "pnpm global virtual store not found: $base" }

$claudeKeep = [regex]::Escape("@$ClaudeVersion")
$codexKeep  = [regex]::Escape("@$CodexVersion")

$candidates = Get-ChildItem $base -Directory | Where-Object {
  ($_.Name -like '@anthropic-ai+claude-code*@*' -and $_.Name -notmatch $claudeKeep) -or
  ($_.Name -like '@openai+codex*@*'            -and $_.Name -notmatch $codexKeep)
}

Write-Host "=== candidates ==="
$candidates | ForEach-Object { $_.FullName }

if (!$Apply) {
  Write-Host "`nPreview only. Re-run with -Apply after checking the list."
  exit 0
}

$before = (Get-PSDrive C).Free
foreach ($dir in $candidates) {
  Remove-Item $dir.FullName -Recurse -Force
  Write-Host "deleted: $($dir.Name)"
}

pnpm store prune

if ($CleanCorepack) { corepack cache clean }
if ($CleanNpmCache) {
  npm cache clean --force
  $npxCache = Join-Path (npm config get cache) "_npx"
  if (Test-Path $npxCache) { Remove-Item $npxCache -Recurse -Force }
}

$after = (Get-PSDrive C).Free
"=== freed: {0:N0} MB ===" -f (($after - $before) / 1MB)

Write-Host "=== verify ==="
claude --version; codex --version; pnpm --version
```

用法：

```powershell
.\cleanup-pnpm.ps1 -ClaudeVersion "2.1.278" -CodexVersion "0.155.1"            # 预览
.\cleanup-pnpm.ps1 -ClaudeVersion "2.1.278" -CodexVersion "0.155.1" -Apply     # 执行
.\cleanup-pnpm.ps1 -ClaudeVersion "2.1.278" -CodexVersion "0.155.1" -Apply -CleanCorepack -CleanNpmCache
```

脚本按"目录名是否含当前版本号"保护当前版本，兼容平台包命名差异；用 `Get-PSDrive` 的实际剩余空间报告释放量，不用 `du` 式加总。

> WSL 侧不再提供对应脚本：pnpm 11+ 没有需要脚本化辨认的旧版本目录，`pnpm store prune -y` 一行足够。旧版指南里的 `cleanup-pnpm.sh` 在 pnpm 12 上会去 `global/5` 找候选、然后 prune `store/v11`，两者互不相干，末尾的 verify 却照样全绿 —— 典型的假安全感，**不要再用**。

---

## 6. 缓存目录速查

| 区域 | WSL 路径 | Windows 路径 | 能否删 |
|---|---|---|---|
| 全局安装（现役） | `~/.local/share/pnpm/global/v11/` | `%LOCALAPPDATA%\pnpm\global\5\.pnpm\` | 不能整删；Windows 侧可删其中旧版本 |
| 全局安装（遗留） | `~/.local/share/pnpm/global/5/` | — | 无 shim 引用即可删 |
| 内容仓库（现役） | `~/.local/share/pnpm/store/v11/` | `pnpm store path` | 用 `pnpm store prune` |
| 内容仓库（遗留） | `~/.local/share/pnpm/store/v10/` | — | 可删，代价是老版 pnpm 要重下 |
| pnpm metadata | `~/.cache/pnpm/` | — | 可删，自动重建 |
| corepack | `~/.cache/node/corepack/` | `corepack cache clean` | 未启用 corepack 就可整删 |
| npm 缓存 | `~/.npm/_cacache`、`~/.npm/_npx` | `npm config get cache` | 可删 |
| Codex 运行时 | `~/.cache/codex-runtimes/` | 用户缓存目录 | **建议保留**，删后会重新下载；本机该目录不存在 |

全局 bin：WSL 在 `~/.local/share/pnpm/bin/`（pnpm 11 起），Windows 在 `%LOCALAPPDATA%\pnpm\` 根目录（pnpm ≤10）。

---

## 7. 日常维护建议

- WSL：`pnpm store prune -y` 就是全部。不需要再去翻全局目录。
- Windows：每次升级 Claude Code / Codex 后看一眼 `global\5\.pnpm\` 是否留了旧版本，先删再 prune。
- 两侧缓存彼此独立，必须分别处理。
- 估算收益用 `du -csh` 去重总计，验收用 `df -h /`。
- `pnpm store prune` 单独跑是安全的日常操作，但在 pnpm ≤10 上它**不能**替代清理全局虚拟 store 里的旧版本。
- 默认保留 `codex-runtimes`。
- 每次 pnpm 大版本升级后，重新确认 `pnpm store path` 和 `pnpm root -g` 的输出——本文所有路径都应以这两条命令的实际结果为准。

---

## 8. 速查

**WSL（pnpm 12）**

```bash
cd ~
pnpm store prune -y
# 首次/换机器时，额外做一次遗留清理：
# rm -rf ~/.local/share/pnpm/global/5 ~/.local/share/pnpm/store/v10 ~/.cache/pnpm ~/.cache/node/corepack
pnpm -v && pnpm ls -g && claude --version && codex --version
```

**Windows（pnpm ≤10）**

```powershell
pnpm ls -g
# 手动删 %LOCALAPPDATA%\pnpm\global\5\.pnpm\ 中确认过的旧 Claude/Codex 目录
pnpm store prune
corepack cache clean          # 可选
npm cache clean --force       # 可选
claude --version; codex --version; pnpm --version
```
