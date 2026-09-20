# Python 踩坑记录

本机环境约定（uv、`PYTHONUNBUFFERED`、不碰系统 `python3`）见 [`../../agent/claude-code/CLAUDE.md`](../../agent/claude-code/CLAUDE.md)。
本文只记**踩过的具体坑**，每条都在本机实测过，附验证方法。

---

## 1. `NO_PROXY` 里的通配符对 `urllib` 无效

### 症状

本机开着代理（Clash，`127.0.0.1:<proxy-port>`）时，Python 用 `urllib` 访问**本机服务**（如 `127.0.0.1:2026`）失败。若把 `no_proxy` 写成 `127.*` 这种省事的通配形式，请求会穿过代理出去，而不是直连。

更难判的是**错误长相**：本机端口没开时，代理返回一个 **HTTP 502 空体**。看起来像"请求失败"，实际是"根本没连到你以为的那个服务"。

### 实测（CPython 3.12.14，2026-09-19）

```python
from urllib.request import proxy_bypass_environment as pbe
```

| `no_proxy` 的值 | `pbe("127.0.0.1:2026")` | 结论 |
| :--- | :--- | :--- |
| `127.*` | **False** | ❌ 通配不生效，走代理 |
| `127.0.0.1` | True | ✅ |
| `localhost,127.0.0.1,::1,.local` | True | ✅ 本机现行配置 |
| `*` | True | ✅ 裸星号被特殊处理，确实绕过一切 |

注意最后两行的对比：**裸 `*` 是被特殊处理的，`127.*` 不是。** 所以"通配符不支持"这个说法要更准确一点——只有独立的 `*` 有效，带前缀的通配形式一律失效。

### 做法

**① shell 里把主机名写全，别图省事用通配。** 本机 [`../../wsl/setup/files/shell_common`](../../wsl/setup/files/shell_common) 第 5 节已经这么做了，并在那里留了注释。

**② 写访问本机服务的代码时，显式绕开代理，不依赖环境变量：**

```python
from urllib.request import build_opener, ProxyHandler

opener = build_opener(ProxyHandler({}))   # 空字典 = 不使用任何代理
resp = opener.open("http://127.0.0.1:2026/api")
```

用 `requests` 的话是 `requests.get(url, proxies={"http": None, "https": None})`。

### 自查

```bash
uv run --python 3.12 python -c '
import os
from urllib.request import proxy_bypass_environment as p
print("当前 no_proxy:", os.environ.get("no_proxy"))
print("本机请求是否绕过代理:", p("127.0.0.1:2026"))'
```

输出 `False` 就说明本机流量正在穿代理。本机现行配置实测为 `True`。

> 注意上面那个 `python -c` 不能省成 `uv run --python 3.12 -c`——`uv run` 会把 `-c`
> 当成自己的参数并报 `unexpected argument '-c' found`。要传给解释器的 flag，必须先写
> `python` 再跟 flag。

---

## 2. f-string 里的引号复用规则，按「字面量部分 / 表达式部分」分开看

中文输出场景特别容易撞上，因为中文标点和引号经常混排。

### 两个部分，规则不同

```python
f"每个{ x }的频道"
  └─字面量─┘└表达式┘└─字面量─┘
```

| 位置 | ≤ 3.11 | ≥ 3.12 (PEP 701) |
| :--- | :--- | :--- |
| **字面量**部分复用同类引号 | ❌ SyntaxError | ❌ **仍然 SyntaxError** |
| **表达式**部分复用同类引号 | ❌ SyntaxError | ✅ 允许 |
| 表达式部分用**不同**引号 | ✅ | ✅ |

**PEP 701 只放开了表达式部分。** 字面量部分永远不行——那个引号会直接把字符串终结掉，和版本无关。

### 实测对照（2026-09-19）

```
                                        3.10.21                      3.12.14
f"每个"从未见过"的频道"      SyntaxError: invalid syntax   SyntaxError: invalid syntax
f"{'zh':>9}"   外双内单      OK                            OK
f"{"zh":>9}"   外双内双      SyntaxError: expecting '}'    OK
f"{ {"a":1}["a"] }"          SyntaxError: unmatched '{'    OK
```

### 写法

```python
f"每个"从未见过"的频道"      # ✗ 任何版本都错
f"每个「从未见过」的频道"     # ✓ 中文引号，推荐
f"每个'从未见过'的频道"       # ✓ 换一种引号
f'每个"从未见过"的频道'       # ✓ 外单内双
```

**要跨版本跑的脚本**（例如本地 3.12、云端 3.10），表达式部分一律**外双内单**，不要依赖 3.12 的新特性。

### ⚠️ 一条流传的错误说法

早先笔记里写「`f"{'中文':>9}"` 在 3.12 能跑、在 3.10 是 SyntaxError」——**这个例子是错的**。它外双内单，属于"不同引号"，实测在 3.10.21 上完全正常。

真正只有 3.12 才能跑的是 `f"{"中文":>9}"`（外双**内双**）。举错例子会让人以为所有格式化都得改，实际只需要盯住"同类引号复用"这一种情况。

同样地，笔记里说报错是 `Perhaps you forgot a comma?`——本机实测两个版本给的都是 `invalid syntax`。那条消息 CPython 确实会在别的上下文给出，但不是这里。

### 自查

```bash
for v in 3.10 3.12; do
  uv run --python $v python -c '
import sys
print(f"Python {sys.version.split()[0]}")
for src in ["f\"{\x27zh\x27:>9}\"", "f\"{\"zh\":>9}\""]:
    try: compile(src, "<t>", "eval"); print(f"  {src:22} OK")
    except SyntaxError as e: print(f"  {src:22} {e.msg}")'
done
```

实测输出：

```
Python 3.10.21
  f"{'zh':>9}"           OK
  f"{"zh":>9}"           f-string: expecting '}'
Python 3.12.14
  f"{'zh':>9}"           OK
  f"{"zh":>9}"           OK
```

---

## 相关

- [`../../agent/claude-code/CLAUDE.md`](../../agent/claude-code/CLAUDE.md) —— uv 规范、`PYTHONUNBUFFERED` 与块缓冲
- [`../../wsl/setup/`](../../wsl/setup/) —— 代理环境变量在哪定义
- [`../skills/wsl-cjk-font/`](../../agent/skills/wsl-cjk-font/) —— matplotlib / Pillow 的中文字体渲染
