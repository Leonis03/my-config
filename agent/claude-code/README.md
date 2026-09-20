# Claude Code 配置

本机 `~/.claude/` 下的配置原件。技能不在这里，在 [`../skills/`](../skills/)。

## 文件

| 仓库中的文件 | 部署到 | 同步于 | 说明 |
| :--- | :--- | :--- | :--- |
| `settings.json` | `~/.claude/settings.json` | 2026-09-20 | 模型、effort、插件、权限、statusLine 挂载点 |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | 2026-09-20 | 全局约定（bx 搜索配方、uv/Python 规范、纯 ASCII 面、技能安装规则） |
| `statusline-command.sh` | `~/.claude/statusline-command.sh` | 2026-09-20 | 状态栏渲染脚本，159 行，纯 bash + jq |

```bash
cp settings.json CLAUDE.md statusline-command.sh ~/.claude/
```

这三个文件与本机**逐字节一致**（不含任何需要脱敏的路径或账户名，所以 `cp` 即可，
不像 [`../skills/`](../skills/) 需要渲染占位符）。核对：

```bash
for f in settings.json CLAUDE.md statusline-command.sh; do
  cmp -s "$f" ~/.claude/"$f" && echo "ok   $f" || echo "DIFF $f"
done
```

三个文件均为**纯 ASCII**，且不含任何凭据。这不只是这三个文件的要求——CLAUDE.md 里
「Keep These Surfaces Pure ASCII」一节把它定成了约定：目录名、文件名、系统与工具的配置文件
（含注释）、以及每个 skill 的 frontmatter（尤其 `description`）都只用 ASCII，正文文档才用中文。

## CLAUDE.md 里的取舍：配方内联，还是留给 skill

曾经写成「跑 `bx` 前必读 skill」，问题是成本结构反了：**CLAUDE.md 每个会话都加载，skill 正文
才是按需加载**。把 2.2k tokens 的 skill 设成搜索前置，等于每次想搜个东西都先交一笔固定税，
而九成场景只需要一行 `bx web ... | jq`。

现在改成 5 条实测过的配方内联（约 400 tokens 常驻），skill 只接边缘情况。盈亏平衡点大约是
「每 5 个会话有 1 个要搜索」，超过就赚。

内联的取舍标准是**「猜错了会不会静默失败」**，只有三条硬约束必须常驻：

- 不加 jq 过滤 = 单次 21k tokens（加了是 180–900），**120 倍**；
- `web` 的结果在 `.web.results[]`，`news`/`images`/`videos`/`places` 在 `.results[]`——
  路径写错返回 **0 行 + exit 0，不报错**；
- `context --max-tokens` 必须 ≥ 1024，否则 422。

反过来，`bx answers` 故意**不**内联：它走独立套餐和独立 key，必须带
`--config ~/.config/brave-search/config-answers.json --no-stream`，猜着用会拿到 exit 3 鉴权错，
看起来像 key 坏了——这种"错得很像另一个问题"的用法，值得多花一次读 skill 的钱。

## settings.json 里几个值得留意的键

| 键 | 值 | 为什么 |
| :--- | :--- | :--- |
| `cleanupPeriodDays` | `3650` | **默认 30 天会静默删除会话记录**。改大以保留历史；下次启动 Claude Code 才生效 |
| `env.API_TIMEOUT_MS` | `600000` | API 超时放宽到 10 分钟，长任务不至于中断 |
| `effortLevel` + `modelSettings` | 均为 `xhigh` | 当前两处都是 xhigh，等于没有分层；若想给弱模型降档，把顶层 `effortLevel` 改成 `high`，由 `modelSettings` 单独抬高 Opus/Sonnet |
| `permissions.defaultMode` | `bypassPermissions` | 跳过工具确认。**换机器时按需调整**，这是信任度很高的设置 |
| `statusLine.command` | `bash ~/.claude/statusline-command.sh` | 用 `bash <path>` 而非裸路径：不需要可执行位，也不写死 `/home/<user>`，拷到别的机器直接能用 |

## statusline 说明

输出形如：

```
<user>@<host>:~/repo Opus 5 ctx:68% in:682k out:386k last:1k cr:110.0M cache:58m hit:99% 5h:62%/124m $12.34
```

设计要点（细节见脚本内注释）：

- **`cr:` 是累计缓存读取**，官方 payload 里没有，需从 transcript 汇总。它通常占账单的大头——API 无状态，每轮重发全部历史。
- **`hit:` 的配色阈值是反的**。命中率越高越好，套用官方的「≥90 红」会把 `hit:99%` 涂成红色。
- **token 计数用亮度渐变而非红黄绿**：它们是活动量不是危险度，`last:30k` 变红会被误读成故障。可用 `SL_MAG_MID` / `SL_MAG_HIGH` / `SL_CR_MID` / `SL_CR_HIGH` 覆盖阈值。
- **`IFS=$'\t'` 不能省**：jq 用 `@tsv` 输出，而模型名（`Opus 5`）含空格，默认按空白分割会导致所有字段串位。
- 单次 jq 提取全部字段。加字段是免费的，加 jq 调用不是（每次 fork 约 4 ms）。官方去抖窗口是 300 ms。
- 依赖 `jq`；没有它状态栏仍能渲染，只是没有指标。

## 相关

- 技能：[`../skills/`](../skills/)
- Shell / WSL 环境：[`../../wsl/setup/`](../../wsl/setup/)
- Git 与 gh：[`../../git-github/`](../../git-github/)
