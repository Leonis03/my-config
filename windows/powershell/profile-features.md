# PowerShell 7 Profile 自定义功能

本文档描述 `$PROFILE`（`C:\Users\<your-windows-user>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`）中通过 PSReadLine 添加的命令行增强功能。

## 概览

| 类别 | 关键绑定 |
|---|---|
| 编辑模式 | Emacs |
| 历史搜索 | `↑` `↓` |
| 历史保存不执行 | `Alt+w` |
| Token 级单词移动 | `Alt+b/f/d/Backspace`、`Alt+B/F` |
| 智能括号 / 引号 | `"` `'` `(` `[` `{` `)` `]` `}` `Backspace` |
| 预测建议接受 | `→`（整条）、`Ctrl+→`（下一词） |
| System32 自动转 ~ | 启动时检测并切回 `~` |
| 终端路径实时上报 | Windows Terminal `OSC 9;9` 实时同步当前工作路径 |

---

## 1. Emacs 编辑模式

```powershell
Set-PSReadLineOption -EditMode Emacs
```

启用 Emacs 风格按键集合，提供 `Ctrl+a/e`（行首/行尾）、`Ctrl+k`（删到行尾）、`Ctrl+y`（粘回 kill-ring）等绑定，是后续 `Alt+*` 绑定的自然搭配。

---

## 2. 历史前缀搜索

```powershell
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
```

- 输入命令前缀（如 `git `）后按 `↑`，只在历史中匹配以该前缀开头的命令
- 反复按 `↑`/`↓` 在匹配项之间循环
- `HistorySearchCursorMovesToEnd` 让光标自动跳到行尾，便于继续编辑
- 输入为空时退化为普通历史浏览

---

## 3. `Alt+w` 暂存当前行到历史

```powershell
Set-PSReadLineKeyHandler -Key Alt+w -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
}
```

**场景**：输入到一半发现需要先做别的事。按 `Alt+w` 后，命令进入历史但**不执行**，命令行清空。完成中间任务后按 `↑` 即可取回继续编辑。

---

## 4. Token 级单词移动

```powershell
Set-PSReadLineKeyHandler -Key Alt+d         -Function ShellKillWord
Set-PSReadLineKeyHandler -Key Alt+Backspace -Function ShellBackwardKillWord
Set-PSReadLineKeyHandler -Key Alt+b         -Function ShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+f         -Function ShellForwardWord
Set-PSReadLineKeyHandler -Key Alt+B         -Function SelectShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+F         -Function SelectShellForwardWord
```

按 PowerShell **解析器 token** 边界移动/删除/选择，而非按字符。

| 按键 | 行为 |
|---|---|
| `Alt+b` / `Alt+f` | 向左 / 向右跳一个 token |
| `Alt+d` | 删除右侧一个 token（进 kill-ring） |
| `Alt+Backspace` | 删除左侧一个 token |
| `Alt+B` / `Alt+F` | 向左 / 向右选中一个 token |

**对比示例**：`git commit -m "fix: bug" --amend`，光标在末尾按一次：
- `Ctrl+←`（字符级）只跳到 `--amend` 的 `amend` 之前
- `Alt+b`（token 级）一次跳到 `--amend` 整个 flag 之前；下一次直接跳过整个带引号字符串 `"fix: bug"`

---

## 5. 智能括号与引号（Smart Insert/Delete）

| 按键 | 行为 |
|---|---|
| `"` `'` | 自动配对插入；选中文本则包裹；位于已有引号末尾时跳过 |
| `(` `[` `{` | 自动插入配对闭合符；选中文本则包裹 |
| `)` `]` `}` | 若光标右侧已是该字符则跳过；否则普通插入 |
| `Backspace` | 若光标位于成对符号之间，**同时删除**两侧字符 |

**示例**：
- 输入 `(` → 自动得到 `()`，光标在中间
- 在 `()` 中间按 `Backspace` → 一次删除整对
- 选中 `foo` 按 `"` → 变成 `"foo"`

引号处理还借助 PowerShell AST：识别 token 类型避免在已有字符串内部错误配对。

---

## 6. 预测建议接受

PSReadLine 的预测插件（如 `PSReadLine` 自带 History 预测、`Az.Tools.Predictor`）会在光标后以灰色显示建议。本配置提供两个粒度的接受方式：

### `→` 接受**整条建议**

```powershell
Set-PSReadLineKeyHandler -Key RightArrow -ScriptBlock {
    if ($cursor -lt $line.Length) { ForwardChar }
    else { AcceptSuggestion }
}
```

- 光标在行内 → 普通右移一格
- 光标在行尾 → 一次接受整条灰色建议（与 zsh / 常见补全习惯一致）

### `Ctrl+→` 接受**下一个词**

```powershell
Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -ScriptBlock {
    if ($cursor -lt $line.Length) { ShellForwardWord }
    else { AcceptNextSuggestionWord }
}
```

- 光标在行内 → 按 token 向右跳一个词（与 `Alt+f` 等价的便捷键）
- 光标在行尾 → 把建议的下一个词追加到命令行

**典型工作流**：输入 `git c` → 灰色显示 `git checkout main`：
- 按 `→` 一次：直接补全为完整命令
- 按 `Ctrl+→` 两次：依次填入 `checkout`、`main`（便于后续修改分支名）

---

## 7. System32 路径自动规避

```powershell
if ($PWD.Path -eq "$env:windir\System32" -or $PWD.Path -eq "$env:windir\SysWOW64") {
    Set-Location ~
}
```

- 当以管理员身份启动终端或通过快捷菜单启动导致初始工作目录为 `System32` 或 `SysWOW64` 时，自动跳转到用户家目录 `~`。
- 仅在启动初始化时执行一次，日常手动 `cd C:\Windows\System32` 不受任何影响。

---

## 8. Windows Terminal 路径实时上报 (OSC 9;9)

```powershell
function prompt {
    $loc = $($ExecutionContext.SessionState.Path.CurrentLocation)
    $esc = [char]27
    $bel = [char]7
    Write-Host -NoNewline "$esc]9;9;`"$loc`"$bel"
    "PS $loc$('>' * ($nestedPromptLevel + 1)) "
}
```

- 向 Windows Terminal 发送 `OSC 9;9` 控制序列，实时告知终端当前 Shell 的实际工作目录。
- **作用**：使得使用 `Ctrl + Shift + D`（复制标签页）或点击 `+`（新建标签页）时，能够实时继承当前正在工作的路径。

---

## 加载方式

```powershell
. $PROFILE   # 当前会话立即生效
```

或重开 PowerShell 7 窗口。

## 文件位置

- Profile：`C:\Users\<your-windows-user>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`
- 官方示例参考：`C:\Users\<your-windows-user>\CODE\PowerShell\SamplePSReadLineProfile.ps1`
