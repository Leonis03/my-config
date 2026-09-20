# Antigravity CLI（agy）— 问题排查

> 使用方式见 [SKILL.zh.md](SKILL.zh.md)。本文档处理使用中出现的各类问题。

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
- **不要用 antissh.sh 的 graftcp 包装**：agy 认 `HTTP_PROXY`，直接用环境变量即可，无需 graftcp（graftcp 虽能靠 ptrace 劫持 Go 的 connect()，但没必要引入）。

## 认证问题

| 现象 | 处理 |
|---|---|
| `Please sign in to view available models` / 卡在认证 | token 过期或刷新失败。**先跑一次交互式 `agy`** 让它重新认证并刷新 token，之后再非交互调用即可 |
| 长时间无响应（无输出，`i/o timeout`） | 没走代理。确认 `HTTPS_PROXY`/`HTTP_PROXY` 已设置；或命令带前缀 `HTTPS_PROXY=http://127.0.0.1:<proxy-port> HTTP_PROXY=http://127.0.0.1:<proxy-port> agy -p "..."` |

认证机制：token 存 `~/.gemini/antigravity-cli/antigravity-oauth-token`，自动刷新；token 过期后 headless 无法自行刷新时，只能靠交互式 `agy` 手动刷新。

## 读图失败

| 现象 | 处理 |
|---|---|
| `a tool required the "read_file" permission ... auto-denied` | settings.json 缺 `permissions` 段，补上 `allow: ["read_file(*)"]`（模板见 SKILL.md） |
| 读图无输出 / 图片未附加 | 路径必须**写在 prompt 文本里**（不是位置参数）；用 WSL 绝对路径（`$HOME/...`） |
| settings.json 是非法 JSON（如单反斜杠 `C:\Users`） | CLI 静默回退 `permissions=<nil>` 全部拒绝——务必用合法 JSON（双反斜杠/正斜杠） |

## 其它

| 现象 | 处理 |
|---|---|
| `Eligibility check failed: ... EOF` | 代理/端点瞬时抖动，**直接重试**（实测偶发，非配置问题） |
| print 模式超时 | 加 `--print-timeout`，如 `--print-timeout 10m` |

## 附：本机已验证事实（2026-08-17）

- `agy` 路径 `$HOME/.local/bin/agy`，v1.1.13，原生 Linux ELF（WSL 直接可用）
- 文字问答、读图均实测通过（带代理环境变量）
- 可用模型（`agy models`）：`gemini-3.7-flash-high/medium/low`（默认）、`gemini-3.6-flash-*`、`gemini-3.5-flash-*`、`gemini-3.1-pro-*`、`claude-sonnet-4-6`、`claude-opus-4-6-thinking`、`gpt-oss-120b-medium`
