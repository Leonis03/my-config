# Brave Search MCP 接入指南

> **适用场景**：设备刚把**第三方 API**（如 Volcengine Ark / DeepSeek / Kimi 等网关）接入 Claude Code，内置 WebSearch 不可用，需要接入 Brave Search 的 MCP 服务器 + API，获得可用的网页搜索能力。
>
> 本文档既是一份操作指南，也包含一段**可直接复制给 Claude 的 Prompt**（见[第一节](#1-直接给-claude-的-prompt)）。

---

## 0. 背景：为什么要用 Brave Search MCP？

Claude Code 内置的 `WebSearch` 工具可能**无法使用**，典型原因：

- **地区限制**：内置 WebSearch 标注为 **US-only**，网络不在美国区域时直接返回 0 条结果；
- **后端不可用**：某些环境中搜索后端未启用/无凭据；
- 与模型无关：第三方 API 网关一般**不影响** WebFetch / MCP 工具的可用性。

**解决方案**：Brave 官方提供成熟的 **Brave Search MCP Server**（`@brave/brave-search-mcp-server`），通过你自己的 Brave API key 提供 8 个搜索工具。

**前提条件**：

| 项目 | 要求 |
|---|---|
| Node.js | ≥ 22（推荐 24+） |
| npm | 随 Node 安装 |
| Brave API key | 到 https://brave.com/search/api/ 注册获取 |
| 网络 | 能访问 `api.search.brave.com`（代理环境需额外配置，见[第 4 步](#4-关键配置代理环境)） |

---

## 1. 直接给 Claude 的 Prompt

> 在**新设备**上，把下面这段复制给 Claude，让它帮你自动完成配置（把 `<你的Brave_API_Key>` 替换成真实 key）：

````markdown
我在这台设备上使用了第三方 API（非 Anthropic 官方）接入 Claude Code。
请帮我接入 Brave Search 的 MCP 服务器，步骤要求如下：

1. 用 `claude mcp add` 添加官方 MCP 服务器：
   claude mcp add brave-search -s user -e BRAVE_API_KEY=<你的Brave_API_Key> -- npx -y @brave/brave-search-mcp-server
2. 如果这台设备需要走本地代理（环境变量里有 HTTPS_PROXY/HTTP_PROXY），
   必须额外给该 MCP 服务器的 env 加上：
   - NODE_USE_ENV_PROXY=1   （关键！让 Node 的 fetch 走环境代理）
   - HTTPS_PROXY=<当前代理地址>
   - HTTP_PROXY=<当前代理地址>
   否则 MCP 服务器会报 "fetch failed"（Node fetch 默认不读代理环境变量）。
3. 验证：`claude mcp list` 应显示 Connected。
4. 提示我重启 Claude Code 使配置生效，然后调用 brave_web_search 做一次真实搜索验证。
````

---

## 2. 获取 Brave API Key

1. 打开 https://brave.com/search/api/ 注册/登录；
2. 选择套餐（个人测试用 **Free** 即可，有一定免费额度；`brave_llm_context` 等工具需要更高套餐）；
3. 在 https://api-dashboard.search.brave.com/app/keys 生成 API key；
4. key 形如 `BSAxxxxxxxxxxxxxxxxxxxxxxxx`，**妥善保管，不要明文分享**。

---

## 3. 添加 MCP 服务器

### 方式 A：命令行（推荐）

```powershell
# -s user = 用户级作用域（所有项目可用）；不写则默认项目级
claude mcp add brave-search -s user -e BRAVE_API_KEY=你的key -- npx -y @brave/brave-search-mcp-server
```

### 方式 B：直接写配置文件

项目级写入项目根目录 `.mcp.json`；用户级写入 `~/.claude.json` 的 `mcpServers` 字段：

```json
{
  "mcpServers": {
    "brave-search": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@brave/brave-search-mcp-server"],
      "env": {
        "BRAVE_API_KEY": "你的key"
      }
    }
  }
}
```

---

## 4. 关键配置：代理环境（90% 故障的来源）

**现象**：配置好后调用搜索，MCP 工具返回 `fetch failed`，但用 PowerShell `Invoke-RestMethod` 直连 API 却是好的。

**根因**：这台设备**所有外网访问必须走本地代理**（例如 Clash / V2Ray，本机监听 `<proxy-port>`）。而：
- PowerShell / curl 会自动使用系统代理 → 成功；
- **Node 的全局 `fetch`（undici）默认不读取 `HTTPS_PROXY` 环境变量** → MCP 服务器连不上外网 → `fetch failed`。

**修复**：给 MCP 服务器的 `env` 加上三项（Node ≥ 24.3 支持 `NODE_USE_ENV_PROXY`）：

```json
"env": {
  "BRAVE_API_KEY": "你的key",
  "NODE_USE_ENV_PROXY": "1",
  "HTTPS_PROXY": "http://127.0.0.1:<proxy-port>",
  "HTTP_PROXY": "http://127.0.0.1:<proxy-port>"
}
```

> 代理端口以本机实际为准（`echo $env:HTTPS_PROXY` 可查）。

**不需要代理的机器**：跳过此项即可。

---

## 5. 生效与验证

1. **重启 Claude Code**（MCP 服务器在会话启动时读取配置，不重启不生效）；
2. 验证服务器注册：
   ```powershell
   claude mcp list
   # 期望输出: brave-search ... ✔ Connected
   ```
3. 让 Claude 实测搜索：
   > 用 brave_web_search 搜索 "Claude Code MCP"，返回 5 条结果。

成功则输出真实搜索结果（标题 + URL + 摘要）。

---

## 6. 工具清单

配置成功后可用以下 8 个工具：

| 工具 | 用途 |
|---|---|
| `brave_web_search` | 通用网页搜索 |
| `brave_news_search` | 新闻搜索（可用 freshness 过滤时间） |
| `brave_local_search` | 本地商户/地点搜索（Pro 计划） |
| `brave_place_search` | 兴趣点 POI 搜索（结构化数据） |
| `brave_image_search` | 图片搜索 |
| `brave_video_search` | 视频搜索 |
| `brave_llm_context` | 提取网页正文给 LLM（RAG 最佳） |
| `brave_summarizer` | AI 摘要（配合 web_search 的 summary:true） |

---

## 7. 故障排查速查表

| 现象 | 原因 | 解决 |
|---|---|---|
| `claude mcp list` 显示 `Connection closed` | 首次运行 npx 还在下载包，健康检查超时 | 手动 `npx -y @brave/brave-search-mcp-server --help` 预热后重试 |
| 调用返回 `fetch failed` | 代理环境未配 `NODE_USE_ENV_PROXY=1` | 见[第 4 步](#4-关键配置代理环境) |
| 返回 0 条结果（偶发） | 代理不稳定 / 冷启动 | 重试；或换更稳定的代理 |
| `Invalid tool name` | 工具名拼写错误 | 用 `claude mcp list` 查看实际工具名 |
| 找不到 key / 401 | key 填错或已撤销 | 检查 `~/.claude.json` 中 `BRAVE_API_KEY` |
| 搜索一直失败但直连 curl 成功 | MCP 进程环境与 shell 环境不同 | 确认 env 三项都写进了 MCP 配置（而非只在 shell） |

---

## 8. 安全提醒

- **API key 明文**存放在 `~/.claude.json`，属于本地配置正常做法，但**不要分享该文件或含 key 的对话记录**；
- 如果 key 曾在对话/日志中明文出现过，建议**轮换**：
  1. 到 Brave 后台生成新 key；
  2. 替换 `~/.claude.json` 中的 `BRAVE_API_KEY`；
  3. 重启 Claude Code 验证新 key 可用；
  4. 再撤销旧 key（让泄露的旧 key 失效）。

---

## 9. 附：本地构建模式（可选，适合调试/改源码）

如果不想依赖 npx 或需要改源码调试，可克隆仓库本地构建：

```bash
git clone https://github.com/brave/brave-search-mcp-server.git
cd brave-search-mcp-server
npm install
npm run build
```

然后配置指向本地入口：

```json
"env": { "BRAVE_API_KEY": "你的key" },
"command": "node",
"args": ["C:\\path\\to\\brave-search-mcp-server\\dist\\index.js"]
```

> Windows 下若用脚本 spawn 该服务器做协议级调试，注意 `.cmd` 不能直接 spawn，可用 `cmd.exe /c` 或直接 `node dist/index.js`。

---

*文档基于 Brave Search MCP Server v2.1.0 + Claude Code MCP 配置实测整理。*
