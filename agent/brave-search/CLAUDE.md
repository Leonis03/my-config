# Brave Search 项目说明

> **2026-09-20 更新**：本机的搜索路径已改为 **`bx` CLI 优先**，本文件原先「内置 WebSearch
> 不可用、请用 MCP 工具」的前提**在 Claude Code 里不成立**（实测可用，见
> [`bx-cli.md` 第 11 节](bx-cli.md#11-与内置-websearch-的分工)）。下面按现状重写。
> 仍需要 MCP 方案的场景（第三方 API 网关、无 shell 的环境）见
> [`brave-search-mcp.md`](brave-search-mcp.md)。

## 网络环境

- 本机（WSL）**无法直连外网**，所有访问必须走本地代理 `http://127.0.0.1:<proxy-port>`。
- `bx` 的代理已由 `~/.local/bin/bx` wrapper 处理（清掉不兼容的 `ALL_PROXY=socks5h://`）。
- MCP 侧的代理配置（`NODE_USE_ENV_PROXY` 等）写在 `~/.claude.json` 的 brave-search 服务器 env 里。

## 搜索怎么走

1. **默认用 `bx` CLI**，配方已内联在全局 `~/.claude/CLAUDE.md` 的 Web Search 一节，
   边缘用法查 `~/.claude/skills/bx/SKILL.md`。
2. **不要加载 `mcp__brave-search__*` 工具**：光一个工具的 schema 约 2,400 tokens，
   且 MCP 返回结果无法用 `jq` 过滤，拿不到 CLI 那个 ~180 tokens 的下限。
3. **要页面正文**用内置 `WebFetch` / `WebSearch`，或 `bx "q" --max-tokens N`。

MCP 服务器仍配置在 `~/.claude.json` 里，作为 CLI 不可用时的退路；工具名如下（不要自行改名）：

| 工具名 | 用途 |
|---|---|
| `brave_web_search` | 通用网页搜索 |
| `brave_news_search` | 新闻搜索（可用 `freshness` 过滤时间） |
| `brave_image_search` | 图片搜索 |
| `brave_video_search` | 视频搜索 |
| `brave_llm_context` | 提取网页正文给 LLM（RAG / 深度阅读） |
| `brave_local_search` | 本地商户/地点（需 Pro 套餐） |
| `brave_place_search` | 兴趣点 POI（结构化数据） |
| `brave_summarizer` | AI 摘要 |

## 使用规则

- **何时搜**：涉及最新信息、实时数据、版本号、或训练数据中可能没有的事实 → 优先搜索。纯代码/逻辑问题不必搜。
- **关键词**：英文关键词效果显著优于中文。
- **禁止臆造**：回答必须基于搜索结果的实际返回内容，不要凭标题或摘要脑补细节；拿不准就再搜一次或如实说明。
- **检查行数**：jq 路径写错是 0 行 + exit 0，不报错。`web` 在 `.web.results[]`，其余在 `.results[]`。
