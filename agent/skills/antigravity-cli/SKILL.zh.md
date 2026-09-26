---
name: antigravity-cli
description: 通过最小权限包装脚本 agy-run.sh，把一次性问答、本地图片、或某个目录内的任务委派给 Google Antigravity CLI（agy，Gemini 3.x）——始终在沙箱内、默认只读，写入与命令权限只能由用户亲自授予。用户要求用 Antigravity / agy / Gemini 问答、要第二意见、识图 / OCR、或在某个目录里干活时触发。你自己能看的图（除非用户点名要 Gemini）、或需要 shell 命令联网的任务，不触发。
allowed-tools: Bash(bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh *)
---

# Antigravity CLI（agy）—— agent 以最小权限调用

**只通过** `scripts/agy-run.sh` 调 agy。不要自己跑 `agy -p`，不要加
`--dangerously-skip-permissions`，不要改 `~/.gemini/antigravity-cli/settings.json`。
Claude Code 钩子 `scripts/agy-guard.sh` 会拦下这三件事，bypassPermissions 模式下也一样。

为什么要包装：裸 `agy -p` 在权限被拒时**以 exit 0 结束、回答为空**，而且不加参数时 shell
命令不进沙箱。`agy-run.sh` 始终加 `--sandbox`、默认从空的临时工作区起步，并把每种结局
映射成退出码。

## 调用

```bash
bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh "question"
bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh --image /abs/shot.png "Transcribe all text exactly"
bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh --dir /abs/project "Summarize README.md"
printf '%s' "$long_prompt" | bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh -
```

| 调用 | 工作区 | agy 能读 | agy 能写 |
|---|---|---|---|
| 不带 `--dir` | 新建的空临时目录，结束即删 | 该目录（含 `--image` 拷进来的图） | 无 |
| `--dir DIR` | `DIR`（不能是 `/`、`$HOME` 或其祖先） | `DIR` | 仅当用户已为 `DIR` 授予写权限 |

选项：`--model NAME`（见 `agy models`；默认用 agy 自己的，目前是 `gemini-3.8-flash-high`）、
`--timeout 10m`、`--dry-run`（显示工作区、参数与最终 prompt，不调模型）、`--keep`
（保留临时工作区）。另有 `quota`（剩余额度，不调模型）与 `grants`（当前规则）。

图片路径用 `--image` 传，不要写进 prompt：脚本会把图拷进工作区，并让 agy 用文件查看工具
打开。问题要具体（"逐字转录"、"截图里是什么报错"），别只说"描述一下"。

## 读结果

stdout 是 agy 的回答；stderr 是诊断信息，最后一行固定为
`agy-run: exit=... model=... workspace=... blocked=... log=...`。

| 退出码 | 含义 | 怎么办 |
|---|---|---|
| 0 | 已回答，无拦截 | 用 stdout；但留意 `agy-run: sandbox:` 提示——某条命令撞上只读路径或没网，回答可能建立在这次失败上 |
| 3 | agy / API 错误 | `RESOURCE_EXHAUSTED`：跑 `quota`；Gemini 与 Claude/GPT 是两个独立额度池（`--model claude-sonnet-4-6`）。登录过期：由用户跑一次交互式 `agy` |
| 4 | 有动作被拦 | 看 `BLOCKED tool(target) -- hint` 行；stdout 可能是半截回答。不要换说法或换工具重试——见「授权」 |
| 5 | 回答为空或不完整 | 重试一次；提示 print timeout 就加大 `--timeout` |
| 6 | 被策略拒绝 | 换一个更窄的 `--dir`，或修正路径 |
| 1、2 | 环境 / 用法错误 | 按报错补齐 |

## 授权——放宽权限由用户决定

1. 遇到带授权提示的 exit 4，先停下。
2. 用 AskUserQuestion 问用户：具体规则（`write_file(/abs/dir)` 或 `command(prefix)`）、
   agy 为什么需要、以及它会**一直生效**到被撤销为止（对之后所有 agy 调用）。
3. 用户同意后，由**用户本人**输入：
   `! bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh grant write /abs/dir`
   或 `... grant command 'uv run'`。你自己不要跑 `grant`，钩子会拦。
4. 重跑。`revoke write|command ...` 与 `grants` 你可以自己跑。

`grant` 拒绝 `/`、`$HOME` 及其祖先，也拒绝 `*` 与 `regex:` 形式的命令规则。
命令规则是**前缀**匹配（`command(ls)` 也放行 `ls -la /anywhere`），把它们关在工作区里的是沙箱。

## agy 能碰到什么（2026-09-26 实测，agy 1.2.11，WSL）

- **文件工具**：工作区无需任何规则即可读；其它位置要 `read_file(...)` 规则（默认没有）。
  写入要 `write_file(DIR)`。agy 默认可写整个 `/tmp`——下面模板里的 `write_file(/tmp)` deny 规则把它关掉。
- **shell 命令**：要有 `command(prefix)` 规则，且始终在沙箱里跑。能看到工作区、系统目录和少数
  家目录（`~/.cache`、`~/.npm`、`~/.nvm` 可写；`~/.config`、`~/.gitconfig` 只读）；家目录其余部分、
  `~/.ssh`、agy 自己的配置都被隐藏。**没有网络**（无 DNS、连不上代理）。umask 为 0000，
  新建文件是所有人可写的。
- 命令不在白名单、或文件工具读工作区外的文件，都会终止 agy 本轮：exit 4。

## 初始配置（每台机器一次）

1. 登录与代理：见 [TROUBLESHOOTING.zh.md](TROUBLESHOOTING.zh.md)。
2. `~/.gemini/antigravity-cli/settings.json` 最小配置：

   ```json
   {
     "permissions": {
       "allow": [],
       "deny": ["write_file(/tmp)"]
     },
     "trustedWorkspaces": ["<your-home>"]
   }
   ```

   `trustedWorkspaces` 对 agy-run 不是必需的（不受信任的临时工作区照样能跑）。规则之后用
   `grant` 加，不要让 agent 手改。
3. Claude Code 钩子，写进 `~/.claude/settings.json`：

   ```json
   "hooks": {
     "PreToolUse": [{
       "matcher": "Bash|Edit|Write|MultiEdit|NotebookEdit",
       "hooks": [{"type": "command", "command": "bash ~/.claude/skills/antigravity-cli/scripts/agy-guard.sh"}]
     }]
   }
   ```
4. 自检：`bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh grants` 会对通配规则或缺少
   `/tmp` deny 发出警告。

出问题了？诊断信息、代理、登录与裸 agy 的行为：**[TROUBLESHOOTING.zh.md](TROUBLESHOOTING.zh.md)**
