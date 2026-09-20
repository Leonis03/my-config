> **中文对照参考，非技能文件。** 本文件不会被任何 Agent harness 加载，仅供人工阅读。
> 行为以 `../SKILL.md` 为准；两者如有出入，以 `SKILL.md` 为准。
> 已刻意移除 YAML frontmatter，以免被 glob `*.md` 的 harness 误识别为重复技能。
> 对应 SKILL.md 版本：2026-09-14 重写版。

# Brave Search (`bx`) 中文对照参考

官方 [Brave Search CLI](https://github.com/brave/brave-search-cli)，位于 `~/.local/bin/bx`。
所有命令将结构化 JSON 输出到 stdout、错误输出到 stderr，并返回机器可读的退出码。

## 规则 0：绝不让原始输出进入上下文

本机实测，一次 `bx web --count 10` 调用：

| 进入上下文的内容 | 字节 | ≈tokens |
|---|---:|---:|
| 裸 JSON，不过滤 | 86,391 | **21,600** |
| jq：标题 + url + 摘要 | 3,585 | 900 |
| jq：仅 url | 716 | **180** |

相差 120 倍。**不带 jq 过滤的 `bx` 调用就是一个 bug。** 必须让 `--count N`
和 jq 投影成对出现。可直接复制的配方见下一节。

## 各命令的输出路径不同，写错会静默失败

`news` / `images` / `videos` / `places` 把结果放在 **顶层**，而不是某个具名键下。
在 `news` 上使用 `.web.results[]` 会返回零行，且退出码为 0、不报任何错误。

| 命令 | jq 配方 |
|---|---|
| `web` | `jq -r '.web.results[] \| "\(.title)\n  \(.url)\n  \(.description)\n"'` |
| `news` | `jq -r '.results[] \| "\(.title)\n  \(.url)  [\(.age)]"'` |
| `images` / `videos` | `jq -r '.results[] \| "\(.title)  \(.url)"'` |
| `places` | `jq -r '.results[] \| "\(.title)  \(.postal_address.displayAddress // "")"'` |
| `context` | `jq -r '.grounding.generic[] \| "[\(.title)] \(.url)\n\(.snippets \| join("\n"))\n"'` |
| `answers` | `jq -r '.choices[0].message.content'` |

`context` 还会返回 `.sources`，它是一个 **以 URL 为键的 object**（不是数组）：
`.sources["https://..."] = {title, hostname, age, snippet}`。

最省的分诊投影，优先用这个：
```bash
bx web "query" --count 10 | jq -r '.web.results[].url'
```

## 如何在 bx 与内置 WebSearch 之间选择

本机两者都可用，且不可互相替代。WebSearch 会抓取并通读页面正文；
`bx web` 只返回标题和摘要。

| 目标 | 用哪个 |
|---|---|
| 广度扫描、分诊、「这个话题上有些什么」 | `bx web/news` + jq（约 180 tok/次） |
| 发布日期、判断「这份资料是否过时」 | `bx` —— WebSearch **没有**任何日期元数据 |
| 时效窗口或明确的日期区间 | `bx news --freshness` —— WebSearch 无此参数 |
| 非美国地区或非英语结果 | `bx --country/--search-lang` —— WebSearch 仅限美国 |
| 机制、引述、页面正文里的具体数字 | **WebSearch**（约 780 tok，已替你读完页面） |
| 限定站点或自定义重排的搜索 | `bx --include-site` / `--goggles` |

用 `bx` 达到页面级深度意味着走 `context`（约 2,400 tok/次），比一次 WebSearch 更贵。
正确做法是：用 `bx` 扫描，再对值得读的 2–3 个 URL 用 WebSearch 或 WebFetch 深入。

## `age` 字段是使用本工具的首要理由

`news` 的结果带 `.age`，`context` 的 `.sources[url].age` 同样带，给出精确发布日期
及其相对形式：

```
"age": ["Thursday, April 16, 2026", "2026-04-16", "151 days ago", "2026-04-16T00:00:00Z"]
```

内置 WebSearch 不暴露任何等价信息。因此 news 投影里应始终带上 `[\(.age)]`，
让时效性可见。

## 快速参考

| 需求 | 命令 |
|---|---|
| 原始网页结果 | `bx web "q" --count 5` |
| 新闻，按时效过滤 | `bx news "q" --freshness pw` |
| 新闻，指定日期区间 | `bx news "q" --freshness 2026-09-01to2026-09-14` |
| RAG grounding（搜索+抓取+抽取一次完成） | `bx "q" --max-tokens 2048`（`bx context` 的别名） |
| AI 合成答案 | `bx answers "q" --config ~/.config/brave-search/config-answers.json --no-stream` |
| 图片 / 视频 | `bx images "q" --count 5` / `bx videos "q" --count 5` |
| 地点 / POI | `bx places "coffee" --location "San Francisco CA US"`（query 是位置参数，**没有** `-q`） |

当前套餐不支持：`bx suggest` 返回 HTTP 400。

## 值得注意的 flag

- `--count N` —— 永远要设。
- `--freshness pd|pw|pm|py` 或 `YYYY-MM-DDtoYYYY-MM-DD`（适用于 `news`、`web`）。
- `--country US|CN|JP|...`、`--search-lang en|zh-hans|ja|...`、`--ui-lang en-US|zh-CN|...`
  —— 本环境下获取非美国结果的唯一途径。`web`、`news`、`context` 均支持。
- `--include-site docs.rs` / `--exclude-site medium.com`（均可重复）/
  `--goggles '$boost=3,site=docs.rs'` 做自定义重排。**三者互斥**，组合使用会以 2 退出。
- `--extra KEY=VALUE` 透传原始 API 参数。实用组合：
  `--extra text_decorations=false` 可去掉 Brave 注入到摘要里的 `<strong>` 标记。
  HTML 实体（`&quot;`、`&#x27;`）仍需自行解码。
- `--offset N` 分页（最大 9）。

`context` 的预算类 flag —— 短名是未在 help 中显示的别名，但实测可用：

- `--max-tokens N` —— **必须 >= 1024**，否则 API 返回 422。2048 是合理上限；
  8192 会向上下文注入约 1 万 tokens。
- `--max-tokens-per-url N`、`--max-urls N`、`--threshold strict|balanced|lenient`
  （对应的规范长名：`--maximum-number-of-tokens`、`--maximum-number-of-urls`、
  `--context-threshold-mode`）。

## 配置与套餐

两把独立的 API key，两个配置文件：

- `~/.config/brave-search/config.json` —— Search 套餐。覆盖 `web`、`news`、
  `images`、`videos`、`places`、`context`。**无需 `--config` 参数。**
- `~/.config/brave-search/config-answers.json` —— Answers 套餐。**`bx answers`
  必须显式指定 `--config <该路径>`**，并加 `--no-stream` 以获得单个完整 JSON
  而非 SSE 流。

用 `bx config show` / `bx config show-key` 查看。`BRAVE_SEARCH_API_KEY` 可覆盖；
完全没有 key 时 CLI 会打印 `error: no API key configured`。

## 不要使用 brave-search MCP server

本机同时配置了 `mcpServers.brave-search`，用的是**同一把 API key**，暴露
`mcp__brave-search__brave_web_search` 等工具。应优先使用本 CLI：
光加载其中一个工具的 schema 就要约 2,400 tokens，而且 MCP 返回的结果无法用 jq
过滤，上面那个 180 token 的下限根本达不到。不要去 ToolSearch 加载它们。

## 代理

这台 WSL 机器的外部流量走本地代理。`~/.local/bin/bx` 这个 wrapper 已经会清除不兼容的
`ALL_PROXY=socks5h://...` 并设置 `HTTPS_PROXY`/`HTTP_PROXY`（`http://127.0.0.1:<proxy-port>`）。
永远不要 unset 这些变量。如需直接调用裸二进制，请用 `~/.local/bin/bx-bin`
并自行清除 `ALL_PROXY`。

## 示例工作流

低成本分诊一个话题，再对要紧的部分深入：
```bash
bx web "axum middleware ordering" --include-site docs.rs --count 10 \
  | jq -r '.web.results[].url'
# 然后对值得读的 2-3 个 URL 用 WebFetch / WebSearch
```

确认某事是否新近发生，并让日期可见：
```bash
bx news "openssl vulnerability" --freshness pw --count 5 \
  | jq -r '.results[] | "\(.title)\n  \(.url)  [\(.age)]"'
```

非美国 / 非英语结果：
```bash
bx web "subagent config" --country CN --search-lang zh-hans --count 5 \
  | jq -r '.web.results[] | "\(.title)  \(.url)"'
```

一次调用拿到某个报错的 grounded 上下文：
```bash
bx "Python TypeError cannot unpack non-iterable NoneType" --max-tokens 2048 \
  | jq -r '.grounding.generic[] | "[\(.title)] \(.url)\n\(.snippets | join("\n"))\n"'
```

AI 合成答案：
```bash
bx answers "Compare PostgreSQL and MySQL for high write throughput" \
  --config ~/.config/brave-search/config-answers.json --no-stream \
  | jq -r '.choices[0].message.content'
```

## 退出码

| 码 | 含义 | 处理 |
|---|---|---|
| 0 | 成功 | 处理 JSON（**要检查行数** —— jq 路径写错同样是 0 行 + 退出码 0） |
| 1 | 客户端错误（4xx） | 修正 query/参数，或该套餐不支持此端点 |
| 2 | 用法错误（flag 不对） | 修正参数；检查是否用了互斥 flag |
| 3 | 认证失败（401/403） | `bx config show-key` |
| 4 | 触发限流（429） | 退避后重试 |
| 5 | 服务端/网络错误 | 检查 127.0.0.1:<proxy-port> 代理，退避后重试 |
