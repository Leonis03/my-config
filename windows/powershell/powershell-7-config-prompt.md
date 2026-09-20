# 任务指令：配置 PowerShell 7 ($PROFILE) 命令行增强功能

请作为 PowerShell 与 Windows 终端配置专家，为当前 Windows 环境下的 **PowerShell 7 (`pwsh`)** 配置 `$PROFILE`，实现以下对话讨论并通过测试的命令行增强功能。

---

## 一、配置目标与核心功能清单

请在 PowerShell 7 配置文件中添加并确保生效以下 6 个核心模块：

### 1. 启用 Emacs 编辑模式
* 设置编辑模式为 `Emacs`（提供 `Ctrl+A`/`Ctrl+E` 行首行尾移动、`Ctrl+K` 剪切等标准绑定）：
  ```powershell
  Set-PSReadLineOption -EditMode Emacs
  ```

### 2. 基于前缀的历史命令搜索
* 绑定方向键 `↑` / `↓` 为前缀历史搜索，并设置光标匹配后自动定位至行尾：
  ```powershell
  Set-PSReadLineOption -HistorySearchCursorMovesToEnd
  Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
  Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
  ```

### 3. `Alt+w` 暂存当前行至历史（不执行）
* 当命令行有未完成输入但需先执行其他命令时，按 `Alt+w` 将当前行推入历史记录并清空当前行，之后可按 `↑` 随时取回：
  ```powershell
  Set-PSReadLineKeyHandler -Key Alt+w -BriefDescription SaveInHistory -ScriptBlock {
      [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)
      [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
  }
  ```

### 4. PowerShell Token 级单词移动、删除与选择
* 按 PowerShell 语法 Token（而非单纯字符）进行快速跳转和编辑：
  ```powershell
  Set-PSReadLineKeyHandler -Key Alt+b         -Function ShellBackwardWord
  Set-PSReadLineKeyHandler -Key Alt+f         -Function ShellForwardWord
  Set-PSReadLineKeyHandler -Key Alt+B         -Function SelectShellBackwardWord
  Set-PSReadLineKeyHandler -Key Alt+F         -Function SelectShellForwardWord
  Set-PSReadLineKeyHandler -Key Alt+d         -Function ShellKillWord
  Set-PSReadLineKeyHandler -Key Alt+Backspace -Function ShellBackwardKillWord
  ```

### 5. 智能括号与引号自动配对（Smart Insert / Delete）
* 自动补全成对的单双引号 `"`、`'` 与括号 `(`、`[`、`{`。
* 选中文本时按引号/括号自动包裹选中内容。
* 光标位于右侧闭合符前再次输入闭合符时直接跳过。
* 在成对符号中间按 `Backspace` 时同时删除两侧成对符号。

### 6. 预测建议接受与按键绑定（核心重点）
* 启用预测源与内联预测视图：
  ```powershell
  Set-PSReadLineOption -PredictionSource HistoryAndPlugin
  Set-PSReadLineOption -PredictionViewStyle InlineView
  ```
* **按 `→` (RightArrow) 接受整条补全建议**：
  * 光标在行内：普通向右移动一个字符（`ForwardChar`）
  * 光标在行尾：接受**整行预测建议**（`AcceptSuggestion`）
* **按 `Ctrl+→` (Ctrl+RightArrow) 接受下一个词**：
  * 光标在行内：按 Token 向右移动一个词（`ShellForwardWord`）
  * 光标在行尾：接受预测建议的**下一个词**（`AcceptNextSuggestionWord`）

### 7. System32 / SysWOW64 自动重定向至 `~`
* 当以管理员身份启动终端导致初始工作目录为 `System32` 或 `SysWOW64` 时，自动跳转到用户家目录 `~`。

### 8. Windows Terminal 路径实时上报（`OSC 9;9`）
* 在 `prompt` 提示符函数中输出 `OSC 9;9` 序列，将当前动态路径实时推送到 Windows Terminal，使得复制标签页（`Ctrl+Shift+D`）与新建标签页能够准确继承工作目录。

---

## 二、执行步骤与安全要求

1. **定位与创建目标文件**：
   * 目标文件为 PowerShell 7 的 `$PROFILE`（通常路径为：`$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`）。
   * 检查其所在目录是否存在，若不存在则先创建目录。

2. **备份现有配置（幂等安全）**：
   * 若 `$PROFILE` 文件已存在，先在同目录下生成备份文件（如 `Microsoft.PowerShell_profile.ps1.bak`）。
   * 检查文件中是否已有重复配置，避免重复追加或按键冲突。

3. **写入/合并配置脚本**：
   * 将以下完整的配置代码优雅地写入/整合进 `$PROFILE`：

```powershell
# ==========================================
# PowerShell 7 PSReadLine 增强配置
# ==========================================
using namespace System.Management.Automation
using namespace System.Management.Automation.Language

Import-Module PSReadLine

# 1. Emacs 编辑模式
Set-PSReadLineOption -EditMode Emacs

# 2. 历史前缀搜索 (按前缀匹配历史命令，光标移动到行尾)
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# 3. Alt+w 暂存当前行至历史 (不执行立即清空，稍后按方向键上可唤回)
Set-PSReadLineKeyHandler -Key Alt+w -BriefDescription SaveInHistory -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
}

# 4. Token 级单词移动、删除与选择 (基于 PowerShell AST Token)
Set-PSReadLineKeyHandler -Key Alt+b         -Function ShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+f         -Function ShellForwardWord
Set-PSReadLineKeyHandler -Key Alt+B         -Function SelectShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+F         -Function SelectShellForwardWord
Set-PSReadLineKeyHandler -Key Alt+d         -Function ShellKillWord
Set-PSReadLineKeyHandler -Key Alt+Backspace -Function ShellBackwardKillWord

# 5. 智能括号与引号 (Smart Insert / Delete)
Set-PSReadLineKeyHandler -Key '"', "'" `
                         -BriefDescription SmartInsertQuote `
                         -LongDescription "Insert paired quotes or wrap selection" `
                         -ScriptBlock {
    param($key, $arg)
    $quote = $key.KeyChar
    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    if ($selectionStart -ne -1) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $quote + $line.SubString($selectionStart, $selectionLength) + $quote)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        return
    }

    if ($cursor -lt $line.Length -and $line[$cursor] -eq $quote) {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        return
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote")
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor - 1)
}

Set-PSReadLineKeyHandler -Key '(', '[', '{' `
                         -BriefDescription SmartInsertOpenParen `
                         -LongDescription "Insert paired parenthesis/bracket/brace or wrap selection" `
                         -ScriptBlock {
    param($key, $arg)
    $closeChar = switch ($key.KeyChar) {
        '(' { ')' }
        '[' { ']' }
        '{' { '}' }
    }
    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    if ($selectionStart -ne -1) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        return
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($key.KeyChar + $closeChar)
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor - 1)
}

Set-PSReadLineKeyHandler -Key ')', ']', '}' `
                         -BriefDescription SmartCloseParen `
                         -LongDescription "Skip closing parenthesis/bracket/brace if present" `
                         -ScriptBlock {
    param($key, $arg)
    if ($cursor -lt $line.Length -and $line[$cursor] -eq $key.KeyChar) {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($key.KeyChar)
    }
}

Set-PSReadLineKeyHandler -Key Backspace `
                         -BriefDescription SmartBackspace `
                         -LongDescription "Delete pair if inside empty quotes or parens" `
                         -ScriptBlock {
    param($key, $arg)
    if ($cursor -gt 0 -and $cursor -lt $line.Length) {
        $left = $line[$cursor - 1]
        $right = $line[$cursor]
        $isPair = ($left -eq '"' -and $right -eq '"') -or
                  ($left -eq "'" -and $right -eq "'") -or
                  ($left -eq '(' -and $right -eq ')') -or
                  ($left -eq '[' -and $right -eq ']') -or
                  ($left -eq '{' -and $right -eq '}')
        if ($isPair) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
            return
        }
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar()
}

# 6. 预测建议与按键补全 (右箭头填整行，Ctrl+右箭头填一词)
Set-PSReadLineOption -PredictionSource HistoryAndPlugin
Set-PSReadLineOption -PredictionViewStyle InlineView

Set-PSReadLineKeyHandler -Key RightArrow `
                         -BriefDescription ForwardCharOrAcceptSuggestion `
                         -LongDescription "Move cursor right, or accept entire suggestion if at end of line" `
                         -ScriptBlock {
    if ($cursor -lt $line.Length) {
        [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar()
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptSuggestion()
    }
}

Set-PSReadLineKeyHandler -Key Ctrl+RightArrow `
                         -BriefDescription ShellForwardWordOrAcceptNextWord `
                         -LongDescription "Move forward token, or accept next suggestion word if at end of line" `
                         -ScriptBlock {
    if ($cursor -lt $line.Length) {
        [Microsoft.PowerShell.PSConsoleReadLine]::ShellForwardWord()
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord()
    }
}

# 7. System32 自动转 ~
if ($PWD.Path -eq "$env:windir\System32" -or $PWD.Path -eq "$env:windir\SysWOW64") {
    Set-Location ~
}

# 8. Windows Terminal 路径实时上报 (OSC 9;9)
function prompt {
    $loc = $($ExecutionContext.SessionState.Path.CurrentLocation)
    $esc = [char]27
    $bel = [char]7
    Write-Host -NoNewline "$esc]9;9;`"$loc`"$bel"
    "PS $loc$('>' * ($nestedPromptLevel + 1)) "
}
```

4. **语法与生效校验**：
   * 运行测试命令检查配置文件是否存在语法解析错误：
     ```powershell
     pwsh -NoProfile -Command "& { . `$PROFILE }"
     ```
   * 确保无任何语法或模块加载报错。

5. **向用户输出配置摘要与快捷键速查表**。
