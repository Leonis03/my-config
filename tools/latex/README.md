# VS Code + LaTeX Workshop

[`settings.json`](settings.json) 是 LaTeX Workshop 的编译工具链与配方。合并进 VS Code 的用户
`settings.json`（不是整个覆盖）。

## 这份配置的取舍

| 取舍 | 为什么 |
| :--- | :--- |
| **默认配方 `latexmk`，走 XeLaTeX** | 中文文档要 XeLaTeX；`latexmk` 自己处理交叉引用要跑几遍的问题 |
| **另留 `xelatex` / `pdflatex` 单次编译** | 排错时要能只跑一遍看原始报错，别让 latexmk 的重试掩盖首次错误 |
| **`-interaction=nonstopmode -file-line-error`** | 不在错误处停下等输入（否则编译挂住像卡死），报错格式带 `file:line:`，VS Code 才能点击跳转 |
| **`-synctex=1`** | 正反向搜索：源码 ↔ PDF 双向定位 |
| **pdf 与 tex 同目录，中间文件进 `build/` 且不自动清理** | 中间文件（`.aux` `.log` `.fls`）是排错证据，自动清掉就没得查了 |
| **显式的 `bibtex` 四步配方** | `pdflatex -> bibtex -> pdflatex x2` 是参考文献能正确解析的最少轮数 |
| **不启用 ChkTeX** | 见下 |

## 坑：ChkTeX 在中文环境刷屏误报

启用 ChkTeX 后，中文文档会刷出大量这样的 warning：

```
19: Use "'" (ASCII 39) instead of "´" (ASCII 180).
```

**成因是字节级的误判。** ChkTeX 不是按 UTF-8 解码后再检查，而是逐字节扫描。汉字的 UTF-8 编码是多字节序列，其中某些后续字节落在 Latin-1 的 `´`（0xB4）等字符位上，ChkTeX 就把它当成了「用错了的排版符号」并报警。

文档里每有若干汉字就可能触发一次，真正的问题淹没在噪音里。**没有配置能豁免**——问题在 ChkTeX 的扫描方式，不在规则集。所以这份配置直接不启用它，而不是逐条 `chktexrc` 去关规则。

## 缺字体 `SimHei` 的离线安装

XeLaTeX 排中文常指定 `SimHei`。如果 Windows 上把中文字体包卸过或做过替换，编译会因为找不到字体而失败。

在线安装命令要从微软服务器拉，网络不稳时反复失败：

```powershell
Add-WindowsCapability -Online -Name "Language.Fonts.Hans~~~und-HANS~0.0.1.0"
```

**离线装法**：从 [my.visualstudio.com/Downloads](https://my.visualstudio.com/Downloads) 搜
`Languages and Optional Features for Windows 11`，下对应版本的 ISO 并挂载，然后指定 `-Source`：

```powershell
Add-WindowsCapability -Online `
  -Name "Language.Fonts.Hans~~~und-HANS~0.0.1.0" `
  -Source "<挂载盘符>:\LanguagesAndOptionalFeatures" `
  -LimitAccess
```

或等价的 DISM 写法：

```powershell
dism /online /add-capability /capabilityname:Language.Fonts.Hans~~~und-HANS~0.0.1.0 `
  /source:<挂载盘符>:\LanguagesAndOptionalFeatures /limitaccess
```

`-LimitAccess` / `/limitaccess` 是关键：**不加的话即使给了 `-Source`，它仍会先去连 Windows Update**，离线就白准备了。

WSL 侧的中文字体是另一套问题（matplotlib 出豆腐块、盘符路径在 WSL 恒不存在），见
[`../../agent/skills/wsl-cjk-font/`](../../agent/skills/wsl-cjk-font/)。
