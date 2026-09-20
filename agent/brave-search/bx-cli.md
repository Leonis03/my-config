# bx —— Brave Search CLI 安装、配置与使用说明

> **适用场景**：需要**发布日期**、**时效窗口**、**非美国/非英语结果**、**站点加权重排**，或需要在 **Claude Code 之外**的 Agent（Antigravity / OpenCode / 脚本）中调用搜索。`bx` 是 Brave 官方出品的单二进制 CLI，JSON 进出、token 预算、专为 AI agent 设计。
>
> 本文档为**本机实测整理**（WSL + Clash 代理环境）。
>
> **v2 更新（2026-09-15）**：升级到 bx **1.7.0**；补全 Answers 套餐的双配置说明；修正 `places` 语法与 `pois` 用途；`spellcheck` 从「未测」改为「不可用」；更正退出码语义；新增 token 纪律与各命令输出路径表。原 v1 基于 1.5.0，下方标注 ⚠️ 的条目是相对 v1 的更正。

---

## 目录

1. [bx 是什么](#1-bx-是什么)
2. [安装与升级](#2-安装与升级)
3. [代理配置（关键）](#3-代理配置关键)
4. [API Key 与双套餐配置](#4-api-key-与双套餐配置)
5. [命令速查](#5-命令速查)
6. [Token 纪律与输出路径](#6-token-纪律与输出路径)
7. [各命令详解与实测](#7-各命令详解与实测)
8. [套餐限制（实测）](#8-套餐限制实测)
9. [退出码](#9-退出码)
10. [常见问题排查](#10-常见问题排查)
11. [与内置 WebSearch 的分工](#11-与内置-websearch-的分工)
12. [供其他 Agent 使用](#12-供其他-agent-使用)
13. [安全提醒](#13-安全提醒)
14. [相关资源](#14-相关资源)

---

## 1. bx 是什么

`bx`（brave-search-cli）是 Brave 官方的网页搜索命令行工具，**v1.7.0**，Rust 编写：

- **单二进制、零运行时依赖**（TLS 用 rustls 静态链接，约 2 MB）；
- **JSON 进出**：所有命令输出 JSON 到 stdout，错误到 stderr，退出码语义化；
- **为 AI agent 设计**：`context` 命令直接返回预提取、按相关度排序的网页正文（token 预算可控），一次调用替代"搜索 → 抓取 → 提取"；
- 支持 Goggles 自定义重排序、`site:` 运算符、新闻/图片/视频/本地 POI 等端点。

与 Brave Search MCP（`@brave/brave-search-mcp-server`）的关系：两者走同一个 Brave API。**但在 Claude Code 里应优先用 CLI**——光加载一个 MCP 工具的 schema 就要约 2,400 tokens，且 MCP 返回结果无法用 `jq` 过滤（见[第 6 节](#6-token-纪律与输出路径)）。

---

## 2. 安装与升级

### 官方安装方式

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/brave/brave-search-cli/main/scripts/install.sh | sh

# 指定版本
VERSION=v1.7.0 curl -fsSL https://raw.githubusercontent.com/brave/brave-search-cli/main/scripts/install.sh | sh

# npm（1.6.0 新增）
npm install -g @brave/brave-search-cli

# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/brave/brave-search-cli/main/scripts/install.ps1 | iex"
```

脚本特性：HTTPS + SHA256 校验、原子安装（`install -m 755`）、安装后自检、无 sudo。环境变量：`VERSION`（默认最新）、`BX_INSTALL_DIR`（默认 `~/.local/bin`）。

### ⚠️ 升级时必须保住 wrapper

**本机 `~/.local/bin/bx` 是 wrapper 脚本，不是二进制**（见[第 3 节](#3-代理配置关键)）。`install.sh` 第 123 行会 `install -m 755 ... "${install_dir}/bx"`，**直接覆盖 wrapper**，代理修复随之失效。

正确的升级流程——装到临时目录，再手动归位到 `bx-bin`：

```bash
# 0. 备份
mkdir -p ~/chat/bx-backup && cp -p ~/.local/bin/bx ~/.local/bin/bx-bin ~/chat/bx-backup/

# 1. 装到临时目录（wrapper 不受影响）
BX_INSTALL_DIR=/tmp/bxnew VERSION=v1.7.0 sh ~/chat/repos/brave-search-cli/scripts/install.sh

# 2. 新二进制归位为 bx-bin
install -m 755 /tmp/bxnew/bx ~/.local/bin/bx-bin

# 3. 验证：版本已更新，wrapper md5 未变
bx --version                      # -> bx 1.7.0
md5sum ~/.local/bin/bx            # -> 应与升级前一致
```

**本机当前状态**：`bx 1.7.0`，wrapper（289 字节，md5 `6d220261...`）+ `bx-bin`（2,102,080 字节静态 ELF）。1.5.0 的旧二进制备份在 `~/chat/bx-backup-1.5.0/`。

### 从源码构建（可选）

```bash
cd ~/chat/repos/brave-search-cli
cargo build --release   # 需 Rust 工具链；产物 ~2MB
make linux-amd64        # -> dist/bx-<version>-linux-amd64
```

> ⚠️ v1 文档里写的源码目录 `~/code/brave/brave-search-cli/` **已不存在**。仓库现 clone 于 `~/chat/repos/brave-search-cli/`。

---

## 3. 代理配置（关键）

本机（WSL）所有外网访问走 Clash 本地代理 `http://127.0.0.1:<proxy-port>`，shell 全局设了 `ALL_PROXY=socks5h://127.0.0.1:<proxy-port>`。这给 `bx` 造成一个踩坑：

### 问题：`bx` 直连报 `Connection refused`（exit 5）

**根因**：`bx` 底层用 Rust `ureq` HTTP 客户端。ureq 按 `ALL_PROXY → HTTPS_PROXY → HTTP_PROXY` 顺序读代理环境变量，但：

- `bx` 构建时**未启用 socks 支持**（`Cargo.toml`：`features=["rustls"]`）；
- `socks5h://` 是 curl 专属写法，ureq 无法解析。

ureq 读到 `ALL_PROXY=socks5h://...` 解析失败 → 回退**直连** → 外网被拒 → `Connection refused`。

### 解决：wrapper 脚本

`~/.local/bin/bx` 是 wrapper（真二进制改名为 `bx-bin`）：

```sh
#!/bin/sh
SELF=$0
case "$SELF" in
    */*) ;;
    *)   SELF=$(command -v bx) ;;
esac
DIR=$(CDPATH= cd -- "$(dirname -- "$SELF")" && pwd)
if [ -n "${HTTPS_PROXY:-}${HTTP_PROXY:-}${https_proxy:-}${http_proxy:-}" ]; then
    export ALL_PROXY=
    export all_proxy=
fi
exec "$DIR/bx-bin" "$@"
```

**原理**：检测到存在 HTTP 代理时清掉 `ALL_PROXY`，让 ureq 改走 `HTTPS_PROXY`/`HTTP_PROXY`。清空**只在 wrapper 子进程内生效**，不污染 shell——curl、git 等能用 socks5h 的工具不受影响。

**1.7.0 下实测复验**：

| 调用方式 | 结果 |
|---|---|
| `bx-bin`（保留 `ALL_PROXY=socks5h`） | `exit 5  error: io: Connection refused` |
| `bx-bin`（手动清 `ALL_PROXY`） | `exit 0` |
| `bx`（wrapper，环境不变） | `exit 0` |

与 Clash 架构兼容：bx 仍走 <proxy-port>，只是换成 HTTP 而非 SOCKS 入口，Clash 照常按规则分流（npmmirror 等国内域名仍走 DIRECT）。

> **注意事项**
> - 不要 unset `HTTPS_PROXY` / `HTTP_PROXY`。
> - 调试真二进制用 `~/.local/bin/bx-bin`，并自行清 `ALL_PROXY`。
> - 更换代理地址只需改环境变量，wrapper 无需改动。

---

## 4. API Key 与双套餐配置

> ⚠️ **这是 v1 文档最大的缺口**：本机实际配了**两把不同的 key、两个独立套餐**，v1 只写了一个。

```
~/.config/brave-search/config.json          key=BSAxxxx...xxxx   Search 套餐
~/.config/brave-search/config-answers.json  key=BSAyyyy...yyyy   Answers 套餐
```

### Search 套餐（默认）

覆盖 `context`、`web`、`news`、`images`、`videos`、`places`、`pois`。**无需 `--config` 参数**。

```bash
bx config set-key              # 交互式（推荐，key 不进 shell 历史）
bx config set-key YOUR_KEY     # 命令行参数
export BRAVE_SEARCH_API_KEY=…  # 环境变量（临时，优先级最高）
```

配置文件 `~/.config/brave-search/config.json`：

```json
{ "api_key": "BSA...", "base_url": "https://api.search.brave.com", "timeout": 30 }
```

查看：`bx config show` · `bx config path` · `bx config show-key`（脱敏）

### Answers 套餐（独立 key）

`bx answers` **必须显式指定** `--config`，否则会用 Search 的 key 并报 `OPTION_NOT_IN_PLAN`：

```bash
# ❌ 用默认 key -> exit 1, option not in plan (400)
bx answers "问题" --no-stream

# ✅ 指定 Answers 配置
bx answers "问题" --no-stream --config ~/.config/brave-search/config-answers.json
```

加 `--no-stream` 得到单个完整 JSON，否则默认 SSE 流式。

> 1.7.0 起：`bx answers` 会在发请求前拒绝不兼容的选项组合（#43），且流式回答不再被 `--timeout` 截断（#39）。

---

## 5. 命令速查

| 需求 | 命令 | 状态 |
|---|---|---|
| RAG 接地（默认命令） | `bx "查询"`（= `bx context "查询"`） | ✅ |
| 原始搜索结果 | `bx web "查询" --count 5` | ✅ |
| 新闻（时效过滤） | `bx news "查询" --freshness pw` | ✅ |
| 图片 | `bx images "查询" --count 5` | ✅ |
| 视频 | `bx videos "查询" --count 5` | ✅ ⚠️v1 标「未测」 |
| 本地地点 / POI 搜索 | `bx places "coffee" --location "San Francisco CA US"` | ✅ ⚠️v1 语法错误 |
| POI 详情（按 ID） | `bx pois PLACE_ID_1 PLACE_ID_2` | ✅ ⚠️v1 误列为搜索命令 |
| AI 综合回答 | `bx answers "问题" --config ~/.config/brave-search/config-answers.json --no-stream` | ✅ ⚠️v1 标「不可用」 |
| 拼写检查 | `bx spellcheck "查询"` | ❌ 不在套餐 ⚠️v1 标「未测」 |
| 联想补全 | `bx suggest "查询"` | ❌ 不在套餐 |

常用全局参数：`--count` · `--country` · `--search-lang` · `--ui-lang` · `--api-key` · `--base-url` · `--timeout` · `--config <path>` · `--extra KEY=VALUE` · `--offset`

> **陷阱**：查询词恰好是子命令名时要写 `bx -- web` 或 `bx context "web"`，否则被当成子命令。

---

## 6. Token 纪律与输出路径

> 本节为 v2 新增。**这是使用 bx 最重要的一条规则。**

### 裸 JSON 会炸上下文

本机实测，一次 `bx web --count 10`：

| 进入上下文的内容 | 字节 | ≈tokens |
|---|---:|---:|
| 裸 JSON，不过滤 | 86,391 | **21,600** |
| jq：标题 + url + 摘要 | 3,585 | 900 |
| jq：仅 url | 716 | **180** |

**相差 120 倍。不带 jq 过滤的 bx 调用就是一个 bug。**

### ⚠️ 各命令的输出路径不同，写错会静默失败

`news` / `images` / `videos` / `places` 把结果放在**顶层** `.results[]`，不是 `.web.results[]`。用错路径返回零行、**退出码仍为 0、不报任何错**。

| 命令 | jq 配方 |
|---|---|
| `web` | `jq -r '.web.results[] \| "\(.title)\n  \(.url)\n  \(.description)\n"'` |
| `news` | `jq -r '.results[] \| "\(.title)\n  \(.url)  [\(.age)]"'` |
| `images` / `videos` | `jq -r '.results[] \| "\(.title)  \(.url)"'` |
| `places` | `jq -r '.results[] \| "\(.title)  \(.postal_address.displayAddress // "")"'` |
| `context` | `jq -r '.grounding.generic[] \| "[\(.title)] \(.url)\n\(.snippets \| join("\n"))\n"'` |
| `answers` | `jq -r '.choices[0].message.content'` |

`context` 另有 `.sources`，是**以 URL 为键的 object**（不是数组）：`.sources["https://..."] = {title, hostname, age, snippet}`。

### 去掉高亮标记

默认返回的 `description` 里混着 `<strong>` 标签：

```bash
bx web "q" --extra text_decorations=false    # API 侧关闭，比事后 gsub 干净
```

HTML 实体（`&quot;`、`&#x27;`）仍需自行解码。

---

## 7. 各命令详解与实测

### 7.1 `bx context` —— RAG 接地（默认命令）

```bash
bx "Python TypeError cannot unpack non-iterable NoneType"   # = bx context "..."
bx "rust serde custom deserializer" --max-tokens 2048 --max-tokens-per-url 1024 --max-urls 5
bx "rust axum middleware" --threshold strict
```

- `--max-tokens` **必须 ≥ 1024**，否则 422。2048 约占上下文 2,400 tokens；8192 约 1 万。
- 短 flag `--max-tokens` / `--max-tokens-per-url` / `--max-urls` / `--threshold` 是**未在 `--help` 中显示的别名**，实测可用；规范长名为 `--maximum-number-of-tokens` / `--maximum-number-of-tokens-per-url` / `--maximum-number-of-urls` / `--context-threshold-mode`。

输出：`.grounding.generic[]` → `{url, title, snippets[]}`，另有 `.sources`（URL 为键的 map，**含 `age` 发布日期**）。

### 7.2 `bx web` —— 原始搜索结果

```bash
bx web "site:docs.rs axum middleware" --count 5
bx web "rust" --result-filter "web,discussions" --count 2          # ✅ 实测可用
bx web "restaurants near me" --lat 37.77 --long -122.41 --city "San Francisco"   # ✅ 实测可用
bx web "subagent config" --country CN --search-lang zh-hans --count 5            # 非美国结果
```

`--result-filter` 可选值：`web, discussions, faq, infobox, news, videos, query, summarizer, locations`

### 7.3 `bx news` —— 新闻

```bash
bx news "openssl vulnerability" --freshness pw --count 5 \
  | jq -r '.results[] | "\(.title)\n  \(.url)  [\(.age)]"'

bx news "AI capex" --freshness 2026-09-01to2026-09-14    # ✅ 日期区间，v1 未提
```

`--freshness`：`pd`（日）/ `pw`（周）/ `pm`（月）/ `py`（年）/ `YYYY-MM-DDtoYYYY-MM-DD`

**`.age` 是 bx 相对内置 WebSearch 的最大优势**——给出精确发布日期：

```json
"age": ["Thursday, April 16, 2026", "2026-04-16", "151 days ago", "2026-04-16T00:00:00Z"]
```

### 7.4 `bx images` / `bx videos`

```bash
bx images "ferris the rust crab" --count 5 | jq -r '.results[] | "\(.title)  \(.url)"'
bx videos "rust async tutorial" --count 5 | jq -r '.results[] | "\(.title)  \(.url)"'
```

> ⚠️ v1 把 `videos` 标为「未测」，实测 ✅ 可用，返回 YouTube 等结果。

### 7.5 `bx places` / `bx pois` —— 本地搜索

> ⚠️ **v1 的语法是错的。** `bx places --location "…" -q "coffee"` 会 `exit 2: unexpected argument '-q'`。**query 是位置参数，没有 `-q`。**

```bash
bx places "coffee" --location "San Francisco CA US"          # ✅ 正确
bx places "pizza" --latitude 37.7749 --longitude -122.4194
bx places "museums" --location "NYC" | jq -r '.results[].title'
```

输出：`.results[]` → `{title, postal_address, contact}`，另有 `addresses / cities / countries / neighborhoods / regions / streets` 等分面。

`pois` **不是搜索命令**，而是按 ID 查详情（营业时间、评分、评论），ID 来自 `places`：

```bash
bx pois PLACE_ID_1 PLACE_ID_2 | jq .
# 直接传查询词会返回 {"type":"local_pois","results":[null]}，exit 0 但无内容
```

### 7.6 站点限定与 Goggles

```bash
bx "rust axum" --include-site docs.rs --include-site github.com     # ✅ 可重复
bx web "rust tutorial" --exclude-site w3schools.com
bx context "TypeError cannot unpack" --goggles '$boost=3,site=docs.python.org'   # ✅ 实测可用
```

**三个 flag 互斥**，组合使用 `exit 2`：

```
error: the argument '--include-site <INCLUDE_SITE>' cannot be used with '--goggles <GOGGLES>'
```

### 7.7 `bx answers` —— AI 回答（OpenAI 兼容）

```bash
bx answers "compare SQLx and Diesel" --no-stream \
  --config ~/.config/brave-search/config-answers.json | jq -r '.choices[0].message.content'

# stdin 模式（✅ 实测可用）
echo '{"messages":[{"role":"user","content":"..."}]}' \
  | bx answers - --no-stream --config ~/.config/brave-search/config-answers.json
```

返回 OpenAI 格式：`.choices[0].message.content` + `.usage`。

> ⚠️ **`answers` 不返回任何引用。** `.choices[0].message` 只有 `content` 和 `role`，无 `citations` / `sources` 字段。正文由 Brave 自己的 `brave-pro` 模型生成，**实测出现过把不同版本的事实压成一句自相矛盾的话**。应视其输出为待核实的线索，而非可据以行动的事实。需要准确性时用内置 WebSearch（返回链接并逐条归因）或回查一手来源。

---

## 8. 套餐限制（实测）

**2026-09-15 于 bx 1.7.0 全量实测**：

| 命令 | 状态 | 备注 |
|---|---|---|
| `context` | ✅ | `--max-tokens` 下限 1024 |
| `web` | ✅ | |
| `news` | ✅ | `--freshness` 含日期区间均生效 |
| `images` | ✅ | |
| `videos` | ✅ | ⚠️ v1 标「未测」 |
| `places` | ✅ | ⚠️ v1 语法错误 |
| `pois` | ✅ | 按 ID 查详情，非搜索 |
| `answers` | ✅ | **需 `--config config-answers.json`**；用默认 key 报 400 |
| `spellcheck` | ❌ | `OPTION_NOT_IN_PLAN` (400) ⚠️ v1 猜测「大概率可用」，实为不可用 |
| `suggest` | ❌ | `OPTION_NOT_IN_PLAN` (400) |

---

## 9. 退出码

以 1.7.0 README 为准（1.7.0 专门修正了 exit 2 的语义，见 #38）。**1 和 2 的分界是「是否真的发出了请求」**：

| 码 | 含义 | 处理建议 |
|---|---|---|
| 0 | 成功 | 处理 JSON——**但要检查行数**，jq 路径写错同样是 0 行 + exit 0 |
| 1 | 请求已发出，但结果不可用 | 修正查询/参数；或套餐不含该端点 |
| 2 | **用法错误——什么都没发出去** | 修正 CLI 参数/配置/输入；不改命令重试无意义 |
| 3 | 认证/权限（401/403） | `bx config show-key` |
| 4 | 限流（429） | 退避重试 |
| 5 | 服务端/网络错误 | 检查代理（127.0.0.1:<proxy-port>），退避重试 |
| 127 | npm launcher 启动失败 | 仅 npm 安装方式；重装或检查平台支持 |

---

## 10. 常见问题排查

| 现象 | 原因 | 解决 |
|---|---|---|
| `error: io: Connection refused`（exit 5） | ureq 读到 `ALL_PROXY=socks5h://` 解析失败回退直连 | 用 wrapper（[第 3 节](#3-代理配置关键)）；或手动清 `ALL_PROXY` |
| 升级后又开始 `Connection refused` | `install.sh` 覆盖了 wrapper | 按[第 2 节](#2-安装与升级)用 `BX_INSTALL_DIR` 重装 |
| `option not in plan`（400）查 answers | 用了 Search 的 key | 加 `--config ~/.config/brave-search/config-answers.json` |
| `option not in plan`（400）查 spellcheck/suggest | 套餐确实不含 | 改用 `context`；或升级套餐 |
| `subscription token invalid`（422） | API key 错误 | `bx config set-key` 重设 |
| `Input should be greater than or equal to 1024`（422） | `context --max-tokens` 低于下限 | 设 ≥ 1024 |
| `unexpected argument '-q' found`（exit 2） | `places` 的 query 是位置参数 | `bx places "coffee" --location "…"` |
| jq 返回 0 行但 exit 0 | 用错输出路径（如对 news 用 `.web.results[]`） | 查[第 6 节](#6-token-纪律与输出路径)的路径表 |
| `unexpected non-JSON response` | 代理返回了 HTML（代理故障页） | 检查 Clash 是否正常 |
| 连续快速调用偶发空结果 | 触发限流，而 `2>/dev/null` 吞掉了错误 | 去掉 `2>/dev/null` 看 stderr；退避重试 |

---

## 11. 与内置 WebSearch 的分工

> v2 新增。**v1 文档开头写「内置 WebSearch 不可用」，在 Claude Code 里这个前提不成立**，本机实测可正常使用。两者是互补关系，不是替代关系。

| 目标 | 用哪个 |
|---|---|
| 广度扫描、分诊、"这话题上有什么" | `bx web/news` + jq（约 180 tok/次） |
| **发布日期**、判断资料是否过时 | `bx` —— WebSearch **没有**任何日期元数据 |
| **时效窗口**或日期区间 | `bx news --freshness` —— WebSearch 无此参数 |
| **非美国地区/非英语**结果 | `bx --country/--search-lang` —— WebSearch 仅限美国 |
| 机制、引述、页面正文里的具体数字 | **WebSearch**（约 780 tok，已替你读完页面） |
| 限定站点或自定义重排 | `bx --include-site` / `--goggles` |

`bx web` 只返回标题和摘要，**不含正文**。用 bx 达到页面级深度要走 `context`（约 2,400 tok/次），比一次 WebSearch 更贵。**正确姿势：用 bx 扫描，再对值得读的 2–3 个 URL 用 WebSearch 或 WebFetch 深入。**

---

## 12. 供其他 Agent 使用

`bx` 不依赖 Claude Code，任何带 shell 的 Agent 都能调用：

```bash
bx "rust axum middleware" --max-tokens 2048
bx web "site:docs.rs axum" --count 5 | jq -r '.web.results[].url'
```

- **代理已由 wrapper 自动处理**：调用方继承的 `ALL_PROXY=socks5h` 不会影响 `bx`（每个进程内自动清理）。
- Claude Code 侧的 skill：`~/.claude/skills/bx/`，结构为 `SKILL.md`（纯 ASCII 主版）+ `references/zh.md`（中文对照，不被 harness 加载）。⚠️ v1 写的 `SKILL.zh.md` 布局已废弃。
- Antigravity 侧：`~/.gemini/config/skills/bx/`，全局约定在 `~/.gemini/config/AGENTS.md`。

**两边的全局约定都内联了 5 条配方**（2026-09-20 起，见 `agent/claude-code/CLAUDE.md` 与
`agent/antigravity/agents-brave-uv.md`），常规搜索不必再先读 skill；skill 只留给 `answers`、
图片/视频/地点、`--goggles`/`--extra`/`--offset`、配置与代理故障、以及任何非零退出码。
两份约定的差别只有一处：Claude Code 侧 `bx` 与内置 WebSearch 分工（见[第 11 节](#11-与内置-websearch-的分工)），
Antigravity 侧内置 `search_web` 太差，**强制全部走 `bx`**，读正文也走 `bx "q" --max-tokens N`。

> `agent/antigravity/agents-brave-uv-desktop.md` 是**另一套环境**的变体（uv 固定 3.13、系统
> Python 3.12），本机 Windows 侧 `C:\Users\<your-windows-user>\.gemini\config\` 下既无
> `AGENTS.md` 也无 `skills/`，即当前未部署。改 WSL 侧约定时不要顺手同步它。
- 复用到其他工具：**用 `cp` 复制目录，不要用软链**——软链在跨文件系统/跨系统拷贝时会失效，且会让 `find` 等审计工具静默漏掉内容。

---

## 13. 安全提醒

- 两把 API key 均明文存放在 `~/.config/brave-search/*.json`，属本地配置正常做法，**不要分享这些文件或含 key 的对话记录**；
- 优先用 `bx config set-key`（交互式）或环境变量，避免 key 进入 shell 历史；
- 若 key 曾在对话/日志中明文出现，建议到 Brave 后台轮换；
- `bx` 内置 SSRF 防护：`--base-url` 只允许 Brave 官方域名或本机回环地址，非回环地址一律拒绝；
- 1.7.0 起配置写入为原子操作且权限收紧（Linux/macOS 下文件 `0600`、目录 `0700`，见 #36）。注意：保存 key 会**替换**文件而非原地写入，所以配置路径上的符号链接、硬链接、bind mount 不会保留。

---

## 14. 相关资源

- 官方仓库：https://github.com/brave/brave-search-cli （本机 clone：`~/chat/repos/brave-search-cli/`）
- 本机安装：`~/.local/bin/bx`（wrapper）+ `~/.local/bin/bx-bin`（真二进制 1.7.0）
- 旧版备份：`~/chat/bx-backup-1.5.0/`
- API Key 后台：https://api-dashboard.search.brave.com
- 相关 skill：`~/.claude/skills/bx/SKILL.md`

---

*文档基于 bx v1.7.0 + WSL/Clash 代理环境实测整理，2026-09-15 更新。*
*核心踩坑：① ureq 无法解析 `ALL_PROXY=socks5h://`，需 wrapper 清空后走 HTTP 代理；② 升级会覆盖 wrapper，须用 `BX_INSTALL_DIR` 绕开；③ `answers` 走独立套餐和独立 key；④ 不加 jq 过滤单次调用 2 万 tokens。*
