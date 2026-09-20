---
name: antigravity-cli-image-read
description: "How to read local images with Antigravity CLI (agy) under strict read-only permissions (no --dangerously-skip-permissions, no command(*))"
metadata: 
  node_type: memory
  type: project
  originSessionId: <session-id>
  modified: <modified-time>
---

# Antigravity CLI（agy）在严格只读权限下读图

> 目标：不使用 `--dangerously-skip-permissions`、也不使用 `command(*)` 全局放行，让 agy 读取本地图片并描述内容。
> 2026-08-12 在 agy v1.1.12 上解决并实测通过。本文合并了当时的完整排查记录。

## 结论

**根本不需要 `command` 权限。**把图片路径写进 prompt 文本里，模型直接用 `ViewFile`/`ReadFile` 读图，全程不碰 shell。

生效配置（`~/.gemini/antigravity-cli/settings.json`）：

```json
"permissions": {
  "allow": ["read_file(*)"],
  "deny": ["write_file(*)"],
  "ask": []
}
```

调用方式（路径嵌入 prompt 文本，**不是**位置参数）：

```bash
agy -p "Describe the content of the image file located at C:\Users\<your-windows-user>\Desktop\test.png"
```

- 默认模型与 `gemini-3.5-flash-high` 均可，`--sandbox` 也能叠加。
- 只读性已实测：模型尝试写文件（shell 命令）会被自动拒绝，未产生文件。
- ⚠️ **位置参数传图在 v1.1.12 已失效**（`agy -p "..." path.png` → "no image was attached"），与 v1.1.11 行为不同。必须把路径写进 prompt 文本。

## 关键发现

1. **`command()` 规则在 v1.1.12 是"精确全字符串匹配"**，不是官方文档所说的"分词前缀正则"。实测 `command(Get-ChildItem)`、`command(Get-ChildItem -Path .*)`、`command(Get-ChildItem -Path *)`、`command(Get-ChildItem -Path C:/Users/<your-windows-user>/(Desktop|Pictures))` 都无法匹配 `Get-ChildItem -Path C:/Users/<your-windows-user>/Desktop`；只有 `command(*)` 匹配一切。
2. 由 1 推出：**基于 command 规则的严格 allowlist 无法覆盖读图工具（内部代号 jetski）的随机命令变体**——此路不通。但也无需再走，因为 ViewFile 路径根本不碰 shell。
3. 图片**可以**绕过 shell：ViewFile 把图片拷进 `.tempmediaStorage` 生成 media artifact，只需 `read_file` 权限。
4. **sandbox 超时的成因**：旧流程靠 shell 命令找图，沙箱内无法访问 Desktop 于是反复重试；改走 ViewFile 后无命令执行，`--sandbox` 可正常完成。
5. `toolPermission` 无需特殊档位，默认 `request-review` + headless 下自动放行 allow 规则即可。

> ⚠️ 排查陷阱：settings.json 若含非法 JSON（例如 `trustedWorkspaces` 里写了单反斜杠 `C:\Users`），CLI 会**静默**回退到 `permissions=<nil>` 并拒绝一切。务必保持合法 JSON（双反斜杠）。

## 背景与已验证事实

- 可执行文件：`C:\Users\<your-windows-user>\AppData\Local\agy\bin\agy.exe`（命令 `agy`）。
- 官方文档（antigravity.google/docs/cli/prompting）只记载 TUI 内 `ctrl+v` 粘贴图片，**没有**命令行传图的官方 flag。
- print/headless 模式下，读图工具 jetski 会执行**多种随机变体**的只读 shell 命令来找图/验证，然后才用 `ReadFile`/`ViewFile` 读图；每条命令都要求 `command` 权限。实测观察到的变体：`pwd`、`Get-ChildItem -Path C:\Users\<your-windows-user>`、`Get-ChildItem -Path C:\Users\<your-windows-user>\Desktop -File`、`Get-ChildItem -Path . -Recurse`、`Get-ChildItem -Path "C:\Users\<your-windows-user>" -Filter *.png -Recurse -ErrorAction SilentlyContinue | Select-Object ...`、`Get-ChildItem -Path C:\Users\<your-windows-user> -Depth 2 -Filter *`。每次运行不完全相同（模型随机选择）——这正是 allowlist 覆盖不住它的原因。
- 权限配置位于 `C:\Users\<your-windows-user>\.gemini\antigravity-cli\settings.json`，规则形如 `action(target)`，评估优先级 **Deny > Ask > Allow**。

### 已试过但失败的方案

| 方案 | allow 规则 | 结果 |
|---|---|---|
| 精确命令 | `command(Get-ChildItem -Recurse -File)` | 拒（jetski 实际命令不同） |
| 前缀 | `command(Get-ChildItem)` | 拒（`Get-ChildItem -Path ...` 被拒） |
| 正则 | `command(Get-ChildItem .*)` | 拒（`Get-ChildItem -Path "..." ...` 被拒） |
| 通配 | `command(Get-ChildItem *)` | 拒（`Get-ChildItem -Path . -Recurse` 被拒） |
| 参数前缀 | `command(Get-ChildItem -Path)` | 拒（本轮 `pwd` 被拒） |
| sandbox | `toolPermission: proceed-in-sandbox` + `enableTerminalSandbox: true` | **超时**（3 分钟无响应；裸 `--sandbox` 跑简单 prompt 正常。成因见「关键发现」第 4 条） |

### 历史备选方案（已不需要）

在找到 ViewFile 路径之前，用黑名单配置也能不带 `--dangerously-skip-permissions` 读图成功，但它放行了 `command(*)`，不满足"严格只读"：

```json
"permissions": {
  "allow": ["command(*)", "read_file(*)", "read_url(*)", "execute_url(*)", "mcp(*)"],
  "deny": ["write_file(*)", "command(rm -rf)", "command(sudo)"],
  "ask": []
}
```

## 验收标准（2026-08-12 全部达成）

- 命令**不含** `--dangerously-skip-permissions` ✅
- settings.json 的 allow 列表**不含** `command(*)` ✅（只有 `read_file(*)`）
- 成功输出 test.png 内容描述（深灰底 + 三行中文：此为测试用图 / 用于验证可通过命令 / 调用 Antigravity CLI 读图）✅ 多次实测通过，含默认模型与 `--sandbox`

## 排查线索与参考

- 本地日志与会话：`~/.gemini/antigravity-cli/` 下的 `cli.log`、`conversations/*.db`（SQLite，`steps` 表的 `step_payload` 是 protobuf，可用 `strings` 或 Python 提取 `CommandLine`）、`brain/<id>/.system_generated/logs/transcript_full.jsonl`
- 权限规则：https://antigravity.google/docs/cli/permissions
- settings 参考：https://antigravity.google/docs/cli/settings
- 命令速查：https://toolsbase.dev/en/reference/antigravity-cli-commands
- 源码：https://github.com/google-antigravity/antigravity-cli ｜ 源码解析：https://deepwiki.com/google-antigravity/antigravity-cli
- 相关 skill：[[antigravity-cli]]（`agent/skills/antigravity-cli/SKILL.md`）
