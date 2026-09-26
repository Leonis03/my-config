---
name: inspect-session
description: Inspect, audit, and analyze coding agent conversation transcripts (Claude Code JSONL, Antigravity/Gemini). Use when the user asks to check what files an agent modified, review Git commits and commands run in a past session, inspect conversation timelines, compare branched DAG forks, search past interactions, or export structured Markdown reports.
---

# Inspect Session

审查、诊断与结构化分析 AI 编程智能体（Claude Code、Antigravity / Gemini CLI）的历史会话记录。

专为回答「**这个会话改了哪些文件？**」、「**对 Git 仓库执行了哪些操作？**」、「**会话分叉后两条路径各自做了什么？**」以及「**将会话导出为整洁的 Markdown 报告**」等场景设计。

---

## 快速使用 (Quick Start)

所有命令均使用系统规范的 Python 运行时执行：

```bash
# 1. 会话总览（统计、角色轮次、工具调用分布、分支拓扑）
PYTHONUNBUFFERED=1 uv run --python 3.10 python ~/.gemini/config/skills/inspect-session/scripts/inspect.py <JSONL_PATH>

# 2. 文件变更与 Git 变更审计（核心：回答会话修改了什么）
PYTHONUNBUFFERED=1 uv run --python 3.10 python ~/.gemini/config/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --changes

# 3. 详细 Git 操作审计（查看所有 git commit, push, diff, status）
PYTHONUNBUFFERED=1 uv run --python 3.10 python ~/.gemini/config/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --git

# 4. 对话时间线流（按时间查看用户输入与模型回应）
PYTHONUNBUFFERED=1 uv run --python 3.10 python ~/.gemini/config/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --timeline

# 5. 错误与失败审计（定位所有抛错工具与退出码）
PYTHONUNBUFFERED=1 uv run --python 3.10 python ~/.gemini/config/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --errors

# 6. 会话内关键词搜索
PYTHONUNBUFFERED=1 uv run --python 3.10 python ~/.gemini/config/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --search "关键词"

# 7. 导出结构化 Markdown 审计报告
PYTHONUNBUFFERED=1 uv run --python 3.10 python ~/.gemini/config/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --export-md /path/to/report.md
```

---

## 核心功能与使用场景

### 1. 变更审计 (`--changes` / `--git`)
当用户询问类似「*这个会话对我的项目改了什么？*」、「*刚才 Claude 提交代码了吗？*」时使用：
- **`--changes`**：自动归纳被创建或编辑的文件列表（包含操作行号、修改行数增减对比 `+X/-Y`、执行成功与否），并附带执行的 Git 命令汇总。
- **`--git`**：逐条列出所有 Git 操作（commit 信息、操作意图说明、原始命令、终端输出预览、退出状态）。

### 2. 分支深度感知与分支对比 (`--diff-branches` / `--branch`)
在 Claude Code 会话因 retry 或并发 resume 发生 DAG 分叉（多分支）时：
- **`--diff-branches 1 2`**：精准定位分叉点（Fork Point），并对比分支 1 和分支 2 在分叉之后：
  - 各自执行了哪些独特的工具调用与文件改动
  - 各自进行了哪些独特的用户对话
  - 辅助用户在运行 `trim-branch` 剪枝前，直观确认应该保留哪一条分支。
- **`--branch N`**：约束任何审计视图（`--summary`, `--changes`, `--timeline` 等），仅沿着第 N 条最深分支的血统链（Leaf -> Root）进行回溯分析。

### 3. 会话时间线 (`--timeline`)
按时间先后顺序展示会话演进：
- `--user-only`：只看用户的 Prompt 轨迹。
- `--tools-only`：只看工具执行流水。
- `--full`：展开完整消息文本（不进行 100 字符省略截断）。
- `--limit N`：限制展示条数。

### 4. 故障排查 (`--errors`)
快速过滤出会话中所有失败的操作：
- 失败的 Bash 命令（非零退出码）
- Hook 拦截警告（如 PreToolUse 守卫拦截）
- 文件编辑失败、权限拒绝或找不到目标内容错误

### 5. 格式兼容性
脚本原生自动识别两类格式，无需显式指定参数：
- **Claude Code 格式**：`~/.claude/projects/.../*.jsonl`（包含 `parentUuid` DAG 拓扑、`ai-title`、`tool_use`、`tool_result`）
- **Antigravity / Gemini 格式**：`~/.gemini/antigravity-cli/brain/.../transcript.jsonl`（包含 `step_index`、`PLANNER_RESPONSE`、`run_command` 等）

---

## 与其他会话技能的分工与联动

- **`inspect-session`**（本技能）：**单会话行为审计与内容解析器**。在已知会话文件路径的前提下，完成零依赖的单会话透视（Git 操作账单、文件修改记录、分支差异对比、导出 Markdown）。
- **`trim-branch`**：**会话外科手术刀**。专精于 DAG 拓扑分叉的切除、单分支安全抽取与原文件覆写。
- **`cass`**：**全局跨会话搜索引擎**。跨 23+ 种 Agent 检索全局历史、关键词找过去的解决方案。
