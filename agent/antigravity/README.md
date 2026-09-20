# Antigravity（Google）

WSL 侧 `~/.gemini/config/` 下的配置原件，加上 `agy` CLI 的使用与排查记录。
技能不在这里，在 [`../skills/`](../skills/)。

CLI 是 **Windows 可执行文件**（`C:\Users\<your-windows-user>\AppData\Local\agy\bin\agy.exe`），
配置和技能却读 WSL 侧的 `~/.gemini/config/`——跨边界这件事贯穿下面所有文档。
另外 `antigravity` 命令指向的是 **Antigravity IDE**，不是 CLI，CLI 是 `agy`。

## 文件

| 仓库中的文件 | 部署到 | 同步于 | 说明 |
| :--- | :--- | :--- | :--- |
| `agents-brave-uv.md` | `~/.gemini/config/AGENTS.md` | 2026-09-20 | 本机（WSL）全局约定：强制 `bx`、uv/Python 3.12、纯 ASCII 面、子代理用 flash |
| `agents-brave-uv-desktop.md` | — | — | **另一套环境**的变体（uv 3.13、系统 Python 3.12）。本机 Windows 侧 `.gemini/config/` 下既无 `AGENTS.md` 也无 `skills/`，即当前未部署；改 WSL 侧约定时不要顺手同步它 |
| `antigravity-cli.md` | — | — | `agy` 用法与实测记录（doc，非 skill；skill 在 [`../skills/antigravity-cli/`](../skills/antigravity-cli/)） |
| `antigravity-cli-image-read.md` | — | — | 严格只读权限下的读图：`read_file(*)` + 路径写进 prompt。含完整排查记录——`command()` 规则实为精确全串匹配、sandbox 超时的成因、失败方案对照 |

```bash
cp agents-brave-uv.md ~/.gemini/config/AGENTS.md
cmp -s agents-brave-uv.md ~/.gemini/config/AGENTS.md && echo ok
```

与本机**逐字节一致**（不含需脱敏的内容，`cp` 即可）。技能目录不能这么拷——
仓库里的 `<your-home>` / `<your-windows-user>` 得先渲染成真值，走
[`../../tools/sync-skills.sh`](../../tools/sync-skills.sh)。

## AGENTS.md 与 Claude Code 侧 CLAUDE.md 的差别

两边共用同一套 skill 目录，全局约定也基本平行（同样的五条 `bx` 配方、同样的 uv 规范、
同样的纯 ASCII 面），只有搜索策略不同：

- **Claude Code**：`bx` 与内置 `WebSearch` 分工——`bx` 扫描拿日期，`WebSearch` 读正文。
- **Antigravity**：内置 `search_web` 太差，**全部走 `bx`**，读正文也用 `bx "q" --max-tokens N`。

因此 AGENTS.md 里多一句提醒：`~/.gemini/config/skills/bx/SKILL.md` 是**两边共用的同一份文件**，
里面那张表会把"读正文"路由到内置 `WebSearch`——在 Antigravity 侧要忽略那几行。
不加这句的话，agent 一读 skill 就会撞上与 AGENTS.md 相反的指示。

## 相关

- 技能：[`../skills/antigravity-cli/`](../skills/antigravity-cli/)
- `bx` CLI 本体：[`../brave-search/bx-cli.md`](../brave-search/bx-cli.md)
- Claude Code 侧对照：[`../claude-code/`](../claude-code/)
