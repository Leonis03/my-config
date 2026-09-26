# Antigravity CLI（agy）— 问题排查

> 使用方式见 [SKILL.zh.md](SKILL.zh.md)。本文档处理使用中出现的各类问题。

## agy-run.sh 的诊断信息

每次运行在 stderr 末尾打印一行 `agy-run: exit=... log=...`；完整的 `stream-json` 记录就在
那个 `log=` 路径（`~/.local/state/agy-run/`，保留最近 50 份）。

| stderr | 含义 | 处理 |
|---|---|---|
| `BLOCKED write_to_file(...) -- needs a write grant` | 目标不在任何 `write_file(...)` 规则内 | 由用户决定：`! bash .../agy-run.sh grant write <dir>` |
| `BLOCKED ... -- a deny rule in ... blocks this` | 命中 `deny` 规则（如 `write_file(/tmp)`） | 本就如此；换个地方写 |
| `BLOCKED run_command(...) -- command not allowlisted` | 没有匹配的 `command(prefix)` 规则 | 由用户决定：`grant command '<prefix>'` |
| `BLOCKED run_command(...) -- command is allowlisted but writes outside a granted dir` | 命令词已放行，但重定向目标没有写权限 | 给目标目录授写权限，或改命令 |
| `BLOCKED view_file(...) -- outside the workspace` | agy 想读工作区外的文件 | 用 `--image` 传，或选一个包含它的 `--dir` |
| `sandbox: <cmd> -> Read-only file system` | 命令写到了沙箱没挂成可写的位置 | 给工作区授写权限，或把输出留在工作区 |
| `sandbox: <cmd> -> Could not resolve host` / `Failed to connect to 127.0.0.1` | 沙箱没有网络，本地代理也连不上 | 联网的活放到 agy 外面做 |
| `agy/API error: RESOURCE_EXHAUSTED`（exit 3） | 额度用完 | `agy-run.sh quota`；用 `--model` 换额度池（Gemini 与 Claude/GPT 分开），或等重置 |
| `... is not valid JSON -- agy would silently deny every tool`（exit 1） | settings.json 解析失败 | 修 JSON（反斜杠要双写、不能有尾逗号） |
| `empty response` / `may be incomplete`（exit 5） | agy 没回任何东西，或撞上 `--print-timeout` | 重试一次；加大 `--timeout` |
| `killed after Ns (hard timeout)`（exit 5） | agy 卡过了 `--timeout` + 120 秒 | 查代理与登录（见下） |

## 裸 agy 的行为，也就是包装脚本要补的坑（agy 1.2.11）

- **被拒会静默结束本轮**：没有 allow 规则的工具被软拒（headless 无法弹窗询问），本轮直接停止，
  `agy -p` 以 **0** 退出、回答为空。只有 `stream-json` 里的 `result.denied_actions` 和 stderr 的
  `jetski: no output produced ...` 能看出来。
- **deny 规则的表现不一样**：工具调用以 `Matches user-configured deny rule` 失败，模型看到错误后
  继续作答；`denied_actions` 仍是 `null`。agy-run 靠工具步骤的 `ERROR` 状态抓它。
- **`command(...)` 规则是按词前缀匹配**（`command(ls)` 放行 `ls -la /etc`）；不加 `--sandbox` 时，
  放行的 `touch /anywhere` 真的会写过去。重定向目标（`> file`）会按 `write_file` 规则检查。
- **headless 下 `--sandbox` 不会自动放行任何命令**：内置的沙箱安全命令表（`cat`、`ls`、`cp` ……）
  照样需要 `command(...)` 规则。
- settings.json 里的 **`"enableTerminalSandbox": true`** 等同于对所有会话（含交互式）加 `--sandbox`。
  `"sandboxAllowNetwork": true` 无效。
- **`--print-timeout` 默认为 0**（等到本轮结束）；agy-run 传 10m。
- **工作区 = 当前目录**：agy 无需任何 `read_file` 规则就能读 cwd。旧模板里的 `read_file(*)`
  多余，而且等于允许 agy 读任何文件。

## 网络与代理（WSL 必须走代理）

- **WSL 直连 Google 被墙**：实测 `dial tcp 172.217.118.4:443: i/o timeout`，时通时断不可靠。agy 必须走代理。
- agy（Go）认 `HTTPS_PROXY`/`HTTP_PROXY` 环境变量，设了即走 HTTP CONNECT。`.bashrc` 已配：
  ```bash
  export HTTPS_PROXY=http://127.0.0.1:<proxy-port>
  export HTTP_PROXY=http://127.0.0.1:<proxy-port>
  export ALL_PROXY=socks5h://127.0.0.1:<proxy-port>   # 给 curl/git 等读 ALL_PROXY 的工具
  ```
- **`ALL_PROXY` 对 agy 无效**：Go 只读 `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`，`ALL_PROXY` 只对 curl/git 等生效。
- **socks5 必须用 `socks5h://`**：WSL 本地 DNS 对 Google 系域名有污染（`www.google.com` → 假地址 `2001::1`），`socks5://`（本地 DNS）连假地址必失败；`socks5h://`（远程 DNS）由 Clash 解析才可用。
- **不要用 antissh.sh 的 graftcp 包装**：agy 认 `HTTP_PROXY`，直接用环境变量即可，无需 graftcp。
- 代理只服务 agy 本身。沙箱里的 shell 命令完全没有网络。

## 认证问题

| 现象 | 处理 |
|---|---|
| `Please sign in to view available models` / 卡在认证 / exit 3 `UNAUTHENTICATED` | token 过期或刷新失败。**由用户跑一次交互式 `agy`** 重新认证，之后非交互调用即可恢复 |
| 长时间无响应（无输出，`i/o timeout`） | 没走代理。确认 `HTTPS_PROXY`/`HTTP_PROXY` 已设置 |

认证机制：token 存 `~/.gemini/antigravity-cli/antigravity-oauth-token`，自动刷新；token 过期后 headless 无法自行刷新时，只能靠交互式 `agy` 手动刷新。沙箱对 shell 命令隐藏了这个目录。

## 读图

- 图片路径必须**写在 prompt 文本里** agy 才会读；位置参数会被静默丢弃。`--image` 替你做了这件事。
- 用 WSL 路径；Windows 路径（`C:\...`）读不到。
- 图在工作区里时，模型用 `view_file` 打开，不需要 shell 命令，也不需要 `read_file` 规则。

## 其它

| 现象 | 处理 |
|---|---|
| `Eligibility check failed: ... EOF` | 代理/端点瞬时抖动，**直接重试** |
| 跑完后 settings.json 键的顺序变了 | agy 启动时会重写该文件，内容不变 |

## 附：本机已验证事实（2026-09-26）

- `agy` 路径 `$HOME/.local/bin/agy`，v1.2.11，原生 Linux ELF。
- 模型（`agy models`）：`gemini-3.8-flash-high/medium/low`（默认 `-high`）、`gemini-3.7-flash-*`、`gemini-3.6-flash-*`、`gemini-3.1-pro-high/low`、`claude-sonnet-4-6`、`claude-opus-4-6-thinking`、`gpt-oss-120b-medium`。
- 额度（`agy-run.sh quota`）：周额度与五小时额度，Gemini 模型与 Claude/GPT 模型各算各的。
- 沙箱挂载（在命令内读 `/proc/self/mountinfo` 所得）：`/` 是空的只读 tmpfs；`/usr`、`/etc`、`/var`、`~/.config`、`~/.gitconfig` 只读；工作区仅在授予写权限时可写；`~/.cache`、`~/.npm`、`~/.nvm`、agy 的草稿目录 `brain/<id>` 与私有的 `/tmp` 可写；工作区父目录的其余部分、`~/.ssh`、`~/.gemini/antigravity-cli`、`~/.gemini/config` 被空的 `deny` 挂载覆盖。seccomp 过滤、无 capabilities、`NoNewPrivs=1`、独立 PID 命名空间、无 DNS 的网络命名空间。
