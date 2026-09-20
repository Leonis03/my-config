---
name: antigravity-cli
description: 调用 Google Antigravity CLI（agy）做一次性纯文本问答或读取本地图片（WSL/Linux 版）。当用户要求调用 Antigravity/agy、执行单个非交互式 prompt、用 gemini-3.x 模型问答、或读取/描述本地图片时触发。
---

# Antigravity CLI（agy）— WSL / Linux 调用

> 本机 `.bashrc` 已配好代理变量（`HTTPS_PROXY`/`HTTP_PROXY=http://127.0.0.1:<proxy-port>`），下面的命令**直接跑即可**。出问题见文末。

## 文字问答

```bash
agy -p "your prompt"          # 一次性问答，输出纯文本
agy -p -                      # 从 stdin 读 prompt（多行/长文本）
agy --model gemini-3.5-flash-high -p "..."   # 指定模型
agy --print-timeout 10m -p "..."             # 覆盖默认 5 分钟超时
```

## 读图（多模态）

**把图片路径写进 prompt 文本**（位置参数传图会静默丢弃，不生效）：

```bash
agy -p "Describe the content of the image file located at $HOME/code/antig/test.png"
```

前置条件：`~/.gemini/antigravity-cli/settings.json` 必须有权限配置（headless 模式默认拒绝一切工具）：

```json
{
  "enableTelemetry": false,
  "permissions": {
    "allow": ["read_file(*)"],
    "deny": ["write_file(*)"]
  },
  "trustedWorkspaces": ["<your-home>"]
}
```

- 模型用 `ViewFile`/`ReadFile` 直接读图，**无需 shell 命令**、无需 `--dangerously-skip-permissions`
- 只读约束有效：模型尝试写文件会被 headless 自动拒绝
- 路径用 WSL 绝对路径（`$HOME/...`），Windows 路径（`C:\...`）读不到
- 实测：test.png（深灰底三行中文）描述正确

## 出问题了？

网络代理 / 卡认证 / token 过期 / 读图失败等调试内容 → 见 **[TROUBLESHOOTING.zh.md](TROUBLESHOOTING.zh.md)**
