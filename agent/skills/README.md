# Skills

18 个 skill，同时供 Claude Code（`~/.claude/skills/`）与 Antigravity（`~/.gemini/config/skills/`）使用。
两边装的集合不同（见下表），但凡是两边都有的，内容保持一致。

## 部署与核对：不能直接 cp

**仓库是脱敏的**：这里写 `<your-home>`、`CourseName`，部署位写的是真实家目录、真实课程名。
两个方向的裸 `cp` 都是 bug——

- **仓库 → 部署**：`antigravity-cli` 的 `trustedWorkspaces` 是 JSON，占位符不会展开，
  照搬过去就是一个字面量 `<your-home>`，Antigravity 认不出这个工作区。
- **部署 → 仓库**：真实路径与账户名进公开仓库，`privacy-gate.sh` 事后才拦得住。

所以走渲染：

```bash
bash ../../tools/sync-skills.sh            # 核对：比对"渲染后"的字节
bash ../../tools/sync-skills.sh deploy     # 部署：展开占位符后写入两个部署位
bash ../../tools/sync-skills.sh deploy bx  # 只处理一个
```

占位符 → 真值的映射在 `tools/.sync-map`（已 gitignore，理由同 `.privacy-names`：
值不写进脚本，脚本本身才能公开）。哈希相同的含义因此是**"仓库 ≡ 部署位，模脱敏"**。

### 家目录：默认写 `$HOME`，展不开才用 `<your-home>`

判据只有一条——**这串字符在使用时会不会被 shell 展开**：

| 情况 | 写什么 | 例子 |
| :--- | :--- | :--- |
| 会被 shell 展开（命令行、脚本、`uv run ...` 的参数、双引号里的 prompt） | `$HOME` | `uv run --python 3.12 python $HOME/.gemini/config/skills/pdf-to-md/scripts/x.py` |
| 展不开，必须是字面路径（JSON、Python 字符串、配置文件的值） | `<your-home>` | `"trustedWorkspaces": ["<your-home>"]` |

所以 `$HOME` **不是**占位符，是原样发布的运行时变量；`<your-home>` 才是，全仓库只剩
`antigravity-cli/SKILL.md` 与 `SKILL.zh.md` 的 `trustedWorkspaces` 那两行（JSON 不做变量展开）。

这条判据的好处是部署出来的 skill 本身就跨机器可用。`deepln-setup/scripts/set-deepln.sh`
和 `gpu-cuda-checks/scripts/smoke-test.sh` 尤其依赖它——这两个脚本会在**租来的 GPU 机**上执行，
家目录根本不是本机的，把 `$HOME` 渲染成真值就等于把脚本钉死在这台机器上。

> 早先这两个记号混用同一个 `$HOME`，渲染时分不清哪个该替换。分开之后 `sync-skills.sh`
> 不需要任何按文件、按路径的例外规则。

### 更好的办法：让代码自己发现，就不必脱敏

占位符是退路，不是首选。**凡是程序能在运行时查出来的值，就不该出现在文本里**——
它既不用脱敏，也不会过期。

| 要拿什么 | 怎么拿 |
| :--- | :--- |
| Linux 家目录（Python） | `Path.home()`，或 `os.path.expanduser("~")`；两者都先看 `$HOME`，未设置时回落到 passwd 记录 |
| Linux 家目录（shell） | `$HOME`，原样写进文档即可 |
| **Windows 账户目录**（WSL 里） | WSL 中**没有** `%USERPROFILE%` 这个环境变量。用通配符：`glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/*.ttf")`；需要确切的用户名时 `wslpath -u "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null \| tr -d '\r')"` |

`wsl-cjk-font` 是这条规则的现成案例，也是个真实事故：它的 `scripts/cjk_font.py` 一直用
`glob.glob("/mnt/c/Users/*/...")` 做得很对，但 `SKILL.md` 里给 agent 照抄的代码片段却把账户名
写死成了另一台机器的值。那个目录在本机不存在，于是 matplotlib 静默回退 DejaVu Sans，出一版
豆腐块**且不抛异常**——正是这个 skill 自己写着要防的失败模式。两处现在都用通配符，
`<your-windows-user>` 这个占位符也就整个消失了。

所以顺序是：**能发现就发现 → 发现不了但 shell 能展开就用 `$HOME` → 都不行才用占位符**。

## 装在哪

| skill | `.claude` | `.gemini` |
| :--- | :---: | :---: |
| `android-chroot-debian` · `antigravity-cli` · `bx` · `deepln-setup` · `find-skills` · `gpu-cuda-checks` · `honor-linuxlab` · `inspect-session` · `shuorenhua` · `termux-debian-external-drive` · `trim-branch` · `wsl-windows-command` | ✅ | ✅ |
| `docx-to-md` · `download-bilibili` · `pdf-to-md` · `video-to-md` · `wsl-cjk-font` | — | ✅ |
| `compress-wsl-space` | — | — |

`antigravity-cli` 在 Claude Code 侧不止是 skill 目录：它的 `scripts/agy-guard.sh` 挂在
`~/.claude/settings.json` 的 PreToolUse 钩子上（见 [`../claude-code/`](../claude-code/)），
负责拦下裸 `agy -p` 与 agent 自行 `grant`。只装 skill 不配钩子，同意闸门就只剩文档约束。

新装一个 skill 是**手动动作**（两边集合本就不同，脚本不会替你决定）；装好之后由
`sync-skills.sh` 维持一致。安装一律 `cp`，不要 `ln -s`——见根目录 README 的「约定」。

## 约定

- **frontmatter 纯 ASCII**，尤其 `description`：它每个会话都加载，并参与触发匹配。
  正文（frontmatter 以下）可以中文。
- 带 `SKILL.zh.md` 的 skill，中文版是对照副本，**不被 harness 加载**，以英文主版为准。
