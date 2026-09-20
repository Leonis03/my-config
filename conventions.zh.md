# 约定

*[English](conventions.md) · 中文（正本）· 回到 [README](README.zh.md)*

- **这些地方只用纯 ASCII**：目录名与文件名、系统与工具的配置文件（**含其中的注释**，注释写英文）、
  每个 skill 的 YAML frontmatter（尤其 `description`，它每个会话都加载并参与触发匹配）。
  正文文档（README、`references/*.md`、skill 的 frontmatter 以下部分）用中文。
  非 ASCII 跑到上面那几处，故障会**静默且远离原因**——跨 WSL/Windows 边界、打包、shell 与 harness 解析。
- **Markdown 文件名一律小写 kebab-case**：`wsl-gui-and-ime.md`，不用大写、下划线或空格。
  取证记录与时点快照在名字末尾加 `-YYYYMMDD`（`etc-diff-analysis-20260330.md`、
  `pnpm-npm-cleanup-20260920.md`），流程型与常青文档不加。
  唯一的例外是**协议性文件名**：`README.md`、`README.zh.md`、`SKILL.md`、`SKILL.zh.md`、
  `CLAUDE.md`、`TROUBLESHOOTING.md`——它们被工具或 harness 按字面查找，改了就失效。
- **根级文档双语，子目录单语**：根目录每篇都是一对——`x.md` 英文（GitHub 默认渲染的那一份）、
  `x.zh.md` 中文正本。目前是 `README` / `conventions` / `redaction` 三对。
  改动先落在中文版，再同步英文版——踩坑索引的措辞是排查结论的浓缩，先用母语写准再翻译。
  **子目录的文档只有中文**，不配英文版；skill 是例外，因为它要被 agent 读，双语各有用处。
- **README 只做落地页与路由**：头部、从哪开始、目录、踩坑索引、许可证。
  成体系又不是每次都要读的内容拆成独立文件，在「从哪开始」那张表里留一行指过去——
  和 skill 用 `SKILL.md` + `references/` 分流是同一套做法。
  踩坑索引**故意留在 README**：它是这个仓库最值得看的东西，挪走会让落地页变成一张空目录。
- **Python 走 `uv`，固定 3.12**。系统 `/usr/bin/python3` 保留给 Ubuntu 的 apt 包，不动它。
- **装 skill 用 `cp`，不用 `ln -s`**。这棵树会在机器、文件系统和操作系统之间搬动，符号链接活不下来。
- **同步 skill 用 `bash tools/sync-skills.sh`，也不要裸 `cp`**。仓库里写的是 `<your-home>`、
  `CourseName` 这类占位符，脚本在写入 `~/.claude/skills/` 与 `~/.gemini/config/skills/`
  时展开成真值，核对时比对**渲染后**的字节——所以"哈希相同"的含义是「仓库 ≡ 部署位，模脱敏」。
  不带参数跑是只读核对。家目录的写法看**会不会被 shell 展开**：会展开就写 `$HOME`（原样发布的
  运行时变量，不是占位符），展不开才写 `<your-home>`——全仓库只剩 JSON 里的两行，
  详见 [`agent/skills/README.md`](agent/skills/README.md)。
- **临时的事情一律在 `tmp/` 里做**：要改之前先备份的副本、脚本的中间产物、想跑一下看看的片段、
  原始命令输出——都放这儿，不要散在仓库根目录，也不要丢进系统 `/tmp`（重启即失，第二天想复看时已经没了）。
  这个目录已 gitignore，`git archive` 导不出去，`privacy-gate.sh` 也**跳过**它，
  所以里面可以放带真实路径和账户名的东西，不会把门禁搞成天天红。
  `tmp/.gitkeep` 是被跟踪的，新 clone 下来目录就在。
- **发布前跑 `bash tools/privacy-gate.sh`**。它只覆盖已知形态，跑通不等于安全——`wsl/storage/` 是原始取证输出，必须人工读。
  账户名**不写在脚本里**（写进去，这个脚本自己就成了泄露源），运行时从 `tools/.privacy-names`（已 gitignore）读取。
- **导出公开副本用 `git archive`，不要 `cp -r`**。`cp -r` 会把靠 gitignore 挡住的本地私有文件一并复制进公开目录。
  本仓库是**私有主仓 + 公开快照**的双仓结构，公开仓自带 `.git`，所以同步流程固定为四步：

  ```bash
  cd ~/dev/my-config                                   # 公开仓
  find . -mindepth 1 -maxdepth 1 -not -name '.git' -exec rm -rf {} +
  ( cd ../my-config-private && git archive HEAD ) | tar -x -C .
  git add -A && git commit && git push
  ```

  **第二步「清空」不能省。** 不清空的话，私有仓里删掉的文件在公开仓会残留——`tar -x` 只覆盖不删除。
  而清空必须 `-not -name '.git'`，否则连仓库本身一起没了。
  **第三步用 `git archive` 而不是 `cp -r`**，这样 `tools/.privacy-names`、`tools/.sync-map`、`tmp/` 天然进不去。
  推送前核一遍：`find . -type f -not -path './.git/*' | git check-ignore --stdin`，应无输出。

  公开仓走**正常历史**，普通 `commit` + `push`，不要 `--amend` 强推——它上线后任何人 clone 过就会被打乱。
  （历史上有两次 amend：一次补许可证、一次改提交消息格式，都在无人 clone 的窗口内。）
- **凭据不进版本库**。需要环境变量形式的 token 时放 `~/.shell_secrets`（`chmod 600`），由 `~/.shell_common` 末尾自动加载。

