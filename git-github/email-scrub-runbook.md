# 清洗 Git 历史中的真实邮箱 —— 操作手册

> **这是一份可直接执行的 runbook。** 把本文件发给一个全新会话（或自己照做），不需要任何额外上下文即可开工。
>
> 背景原理、隐私邮箱的由来、gh 配置等见同目录 [`README.md`](README.md) 第一、五节。本文只管**怎么安全地执行**。

**快照时间：2026-09-19**。仓库清单会随时间变化，执行前先跑第 3 节重新扫描。

> [!IMPORTANT]
> 本文中的 `your-old-email@example.com` 是**占位符**，本仓库出于脱敏考虑不保存真实邮箱。
> 执行前先全文替换为要清除的那个真实地址（共 5 处：第 0、3.2、5.1、6、7.1 节）：
>
> ```bash
> sed -i 's#your-old-email@example\.com#你的真实邮箱#g' email-scrub-runbook.md
> ```
>
> 替换后**不要提交这个改动**——用完 `git checkout -- email-scrub-runbook.md` 还原。

---

## 0. 三十秒速览

```
要清除的邮箱      your-old-email@example.com
要替换成          Leo <28289630+Leonis03@users.noreply.github.com>
工具              git-filter-repo（已安装 /usr/bin/git-filter-repo）
本机待清仓库      5 个，均无 remote，均在 ~/code 下
最大的坑          filter-repo 会静默销毁未提交的【已跟踪文件】修改 —— 见第 2 节
```

---

## 1. 为什么要做

GitHub 的 "Keep my email addresses private" 只管住网页端操作。本地 `git commit` 时如果 `user.email` 是真实邮箱，它会被**永久固化进 commit 元数据**，改配置也救不回已有历史——只能重写历史。

本机全局身份已经配好（2026-09-19 起）：

```bash
git config --global user.email    # 28289630+Leonis03@users.noreply.github.com
git config --global user.name     # Leo
```

所以**新提交是干净的**，本手册只处理存量历史。

---

## 2. ⚠️ 必读：一个会静默丢数据的坑

`git filter-repo --force` 重写完历史后会**硬重置工作区**。已跟踪文件的未提交修改会被 HEAD 的内容覆盖，**没有任何提示**。

实测（2026-09-19，拿 `repo-3` 的副本跑）：

```
执行前   12 条 dirty  =  5 个 ' M' 已跟踪修改  +  7 个 '??' 未跟踪
执行后    7 条 dirty  =                           7 个 '??' 未跟踪
                         ↑ 5 个修改被静默覆盖，内容回退到 HEAD
```

未跟踪文件（`??`）不受影响，**已跟踪文件的修改会丢**。

> **`cp -r .git .git.bak` 救不了你。** 那只备份了仓库数据库。工作区文件此刻已被覆盖，恢复 `.git.bak` 也拿不回那 5 处修改。
>
> **正确做法**：备份**整个目录**，或者先把修改 commit / stash 掉。见第 4、5 节。

---

## 3. 前置检查

### 3.1 工具就位

```bash
git filter-repo --help >/dev/null 2>&1 && echo "OK" || sudo apt install -y git-filter-repo
```

> Debian 打包版的 `git filter-repo --version` 打印的是 commit 哈希（如 `ed61b4050b71`）而不是版本号，不是故障。用 `--help` 判断是否可用更可靠。

### 3.2 重新扫描待清仓库（不要信本文的快照，以实扫为准）

```bash
TARGET_EMAIL='your-old-email@example.com'

printf '%-34s %8s %8s %8s %10s\n' "REPO" "HITS" "COMMITS" "REMOTE" "DIRTY-TRACKED"
find ~/code -name .git -type d -prune 2>/dev/null | sort | while read -r g; do
  d="${g%/.git}"
  n=$(git -C "$d" log --all --format='%ae%n%ce' 2>/dev/null | grep -c "$TARGET_EMAIL")
  [ "$n" -eq 0 ] && continue
  t=$(git -C "$d" log --all --oneline 2>/dev/null | wc -l)
  r=$(git -C "$d" remote 2>/dev/null | head -1); r=${r:-none}
  md=$(git -C "$d" status --porcelain --untracked-files=no 2>/dev/null | wc -l)
  printf '%-34s %8s %8s %8s %10s\n' "${d#$HOME/code/}" "$n" "$t" "$r" "$md"
done
```

`DIRTY-TRACKED` 那列**不为 0 的仓库，必须先处理第 4 节，否则会丢数据**。

---

## 4. 工作清单与门禁

### 4.1 快照（2026-09-19）

| 仓库（`~/code/` 下） | 命中条目 | 总提交 | remote | 未提交(已跟踪) |
| :--- | ---: | ---: | :--- | ---: |
| `proj-a/sub/repo-1` | 16 | 8 | 无 | **2** ⚠️ |
| `proj-a/repo-2` | 16 | 8 | 无 | 0 |
| `repo-3` | 14 | 7 | 无 | **5** ⚠️ |
| `repo-4` | 4 | 2 | 无 | **1** ⚠️ |
| `repo-5` | 2 | 1 | 无 | 0 |

合计 52 条身份记录、26 次提交。**5 个仓库全部没有 remote**，所以不涉及强制推送，公网无泄露——这是一次纯本地清理。

> `proj-a/sub/repo-1` 与 `proj-a/repo-2` 的数字完全相同，很可能互为副本。两个都要清。

### 4.2 门禁：先让工作区干净

对 `DIRTY-TRACKED` 不为 0 的仓库，三选一：

```bash
cd ~/code/<repo>

# 方案 A：提交掉（推荐，改动就此进入历史，且会用新的隐私身份）
git add -A && git commit -m "wip: save before history rewrite"

# 方案 B：暂存
git stash push -u -m "before history rewrite"
#   注意：stash 也是 commit 对象，会带上当前身份。身份已配好所以没问题。
#   清洗后 git stash pop 即可。

# 方案 C：不想动改动，就整目录备份后照跑（改动仍会丢，但能从备份取回）
cp -r ~/code/<repo> ~/code/<repo>.bak-$(date +%Y%m%d)
```

确认门禁通过：

```bash
git status --porcelain --untracked-files=no   # 必须无输出
```

---

## 5. 执行：本地仓库（无 remote）

### 5.1 准备 mailmap

```bash
cat > /tmp/mailmap <<'EOF'
Leo <28289630+Leonis03@users.noreply.github.com> <your-old-email@example.com>
EOF
```

格式是 `新名字 <新邮箱> <旧邮箱>`——匹配旧邮箱，同时替换名字和邮箱。

### 5.2 逐仓库清洗

**建议一次只做一个仓库，做完验证再做下一个。** 下面的循环带门禁，会自动跳过脏仓库：

```bash
REPOS=(
  "$HOME/code/proj-a/sub/repo-1"
  "$HOME/code/proj-a/repo-2"
  "$HOME/code/repo-3"
  "$HOME/code/repo-4"
  "$HOME/code/repo-5"
)

for d in "${REPOS[@]}"; do
  echo "==================== $d ===================="

  # 门禁：有未提交的已跟踪修改就跳过，不冒险
  if [ -n "$(git -C "$d" status --porcelain --untracked-files=no)" ]; then
    echo "  SKIP: 有未提交的已跟踪修改，先处理第 4.2 节"
    continue
  fi

  # 备份整个目录（不是只备份 .git）
  cp -r "$d" "${d}.bak-$(date +%Y%m%d-%H%M%S)"

  # 重写
  git -C "$d" filter-repo --mailmap /tmp/mailmap --force

  # 立即验证
  echo "  --- 重写后的身份 ---"
  git -C "$d" log --all --format='  %an <%ae> | %cn <%ce>' | sort -u
done

rm -f /tmp/mailmap
```

---

## 6. 执行：带 remote 的仓库（需要强推）

> [!WARNING]
> 重写历史会改变所有受影响 commit 的 SHA。强制推送会覆盖远端历史。**操作前确认该仓库无他人协作。**

本机当前 5 个目标仓库都没有 remote，本节备查（笔记本当初对 `repo-a` / `repo-b` / `repo-d` 就是这么做的）：

```bash
mkdir -p /tmp/gitrewrite && cd /tmp/gitrewrite
cat > mailmap <<'EOF'
Leo <28289630+Leonis03@users.noreply.github.com> <your-old-email@example.com>
EOF

for repo in repo-a repo-b repo-d; do
  git clone --bare "https://github.com/Leonis03/$repo.git" "$repo.git"
  cd "$repo.git"
  git filter-repo --mailmap /tmp/gitrewrite/mailmap --force
  git log --all --format='%an <%ae> | %cn <%ce>' | sort -u      # 先看，确认干净
  git remote add origin "https://github.com/Leonis03/$repo.git" # filter-repo 会移除 origin
  git push --force --mirror origin
  cd /tmp/gitrewrite
done

cd ~ && rm -rf /tmp/gitrewrite
```

用 bare clone 而不是就地重写，天然规避了第 2 节那个工作区被覆盖的问题。

---

## 7. 验证

### 7.1 本地

```bash
# 应该没有任何输出
for d in ~/code/proj-a/sub/repo-1 ~/code/proj-a/repo-2 ~/code/repo-3 ~/code/repo-4 ~/code/repo-5; do
  git -C "$d" log --all --format='%ae%n%ce' 2>/dev/null | grep 'your-old-email@example.com' && echo "  !! 残留: $d"
done
echo "扫描完成"
```

### 7.2 远端（对有 remote 的仓库）

```bash
gh api "repos/Leonis03/<repo>/commits?per_page=100" \
  --jq '.[] | "\(.commit.author.name) <\(.commit.author.email)>"' | sort -u
```

### 7.3 确认新提交身份正确

```bash
git -C <任一仓库> log -1 --format='%an <%ae>'
```

---

## 8. 回滚

第 5 节每个仓库都留了整目录备份：

```bash
ls -d ~/code/*.bak-*  ~/code/*/*.bak-*  2>/dev/null

# 回滚
rm -rf ~/code/<repo>
mv ~/code/<repo>.bak-<时间戳> ~/code/<repo>
```

验证无误后再删备份：

```bash
rm -rf ~/code/<repo>.bak-<时间戳>
```

---

## 9. 已知行为（不是 bug）

| 现象 | 说明 |
| :--- | :--- |
| 未提交的**已跟踪**修改消失 | 第 2 节。这是硬重置的后果，只能靠门禁或备份规避 |
| 未跟踪文件（`??`）安然无恙 | filter-repo 不碰它们 |
| `origin` 不见了 | filter-repo 的有意设计，防止误推。需要就 `git remote add` 加回 |
| 作者**名字**也变了 | mailmap 左侧写了 `Leo`，所以 `Leonis03` → `Leo`。这是期望行为 |
| 所有 commit SHA 变了 | 重写历史的必然结果。无 remote 的仓库不受影响；有 remote 的必须强推 |
| `git filter-repo --version` 打印哈希 | Debian 打包版的行为，不是故障 |
| 提示 "not a fresh clone" | `--force` 已经处理。就地重写必须带这个参数 |

---

## 10. 收尾

1. 跑第 7.1 节确认零残留
2. 确认备份目录里的东西都不需要了，删掉 `*.bak-*`
3. 如果第 4.2 节用了 stash，逐个 `git stash pop`
4. 把本文件的第 4.1 节快照更新为「已完成」，或直接删掉该表

---

## 相关

- [`README.md`](README.md) —— 隐私邮箱原理、gh 登录与凭据、代理调优、WSL 浏览器唤起与已知坑
- [`../wsl/setup/`](../wsl/setup/) —— shell 与 WSL 环境
- [`../agent/claude-code/`](../agent/claude-code/) —— Claude Code 配置
