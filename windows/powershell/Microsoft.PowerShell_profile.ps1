# ==============================================================================
# PowerShell 7 PSReadLine Enhancement Configuration
# Note: Keep this file in pure ASCII encoding for portability.
# ==============================================================================

using namespace System.Management.Automation
using namespace System.Management.Automation.Language

Import-Module PSReadLine

# ------------------------------------------------------------------------------
# 1. Emacs Edit Mode (Provides Ctrl+A, Ctrl+E, Ctrl+K, Ctrl+Y, etc.)
# ------------------------------------------------------------------------------
Set-PSReadLineOption -EditMode Emacs

# ------------------------------------------------------------------------------
# 2. History Prefix Search (Search history matching prefix, cursor moves to end)
# ------------------------------------------------------------------------------
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# ------------------------------------------------------------------------------
# 3. Alt+w: Save Current Line to History (Do not execute, recall with UpArrow)
# ------------------------------------------------------------------------------
Set-PSReadLineKeyHandler -Key Alt+w `
                         -BriefDescription SaveInHistory `
                         -LongDescription "Save current line in history but do not execute" `
                         -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
}

# ------------------------------------------------------------------------------
# 4. Token-Level Navigation, Deletion, and Selection (PowerShell AST Tokens)
# ------------------------------------------------------------------------------
Set-PSReadLineKeyHandler -Key Alt+b         -Function ShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+f         -Function ShellForwardWord
Set-PSReadLineKeyHandler -Key Alt+B         -Function SelectShellBackwardWord
Set-PSReadLineKeyHandler -Key Alt+F         -Function SelectShellForwardWord
Set-PSReadLineKeyHandler -Key Alt+d         -Function ShellKillWord
Set-PSReadLineKeyHandler -Key Alt+Backspace -Function ShellBackwardKillWord

# ------------------------------------------------------------------------------
# 5. Smart Quotes and Parentheses / Brackets Pairing (Smart Insert / Delete)
# ------------------------------------------------------------------------------

# 5.1 Smart quotes: auto-pair, wrap selection, or skip closing quote
Set-PSReadLineKeyHandler -Key '"', "'" `
                         -BriefDescription SmartInsertQuote `
                         -LongDescription "Insert paired quotes or wrap selection" `
                         -ScriptBlock {
    param($key, $arg)

    $quote = $key.KeyChar

    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    # Wrap selection in quotes if text is selected
    if ($selectionStart -ne -1) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
            $selectionStart,
            $selectionLength,
            $quote + $line.SubString($selectionStart, $selectionLength) + $quote
        )
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        return
    }

    # AST token inspection
    $ast = $null
    $tokens = $null
    $parseErrors = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$null)

    function FindToken {
        param($tokens, $cursor)
        foreach ($token in $tokens) {
            if ($cursor -lt $token.Extent.StartOffset) { continue }
            if ($cursor -lt $token.Extent.EndOffset) {
                $result = $token
                $token = $token -as [StringExpandableToken]
                if ($token) {
                    $nested = FindToken $token.NestedTokens $cursor
                    if ($nested) { $result = $nested }
                }
                return $result
            }
        }
        return $null
    }

    $token = FindToken $tokens $cursor

    # Inside a quoted string token
    if ($token -is [StringToken] -and $token.Kind -ne [TokenKind]::Generic) {
        if ($token.Extent.StartOffset -eq $cursor) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote ")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            return
        }
        if ($token.Extent.EndOffset -eq ($cursor + 1) -and $line[$cursor] -eq $quote) {
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            return
        }
    }

    if ($null -eq $token -or
        $token.Kind -eq [TokenKind]::RParen -or
        $token.Kind -eq [TokenKind]::RCurly -or
        $token.Kind -eq [TokenKind]::RBracket) {
        if ($line[0..$cursor].Where{ $_ -eq $quote }.Count % 2 -eq 1) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
        } else {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
        return
    }

    # Wrap token if cursor is at token start
    if ($token.Extent.StartOffset -eq $cursor) {
        if ($token.Kind -eq [TokenKind]::Generic -or
            $token.Kind -eq [TokenKind]::Identifier -or
            $token.Kind -eq [TokenKind]::Variable -or
            $token.TokenFlags.hasFlag([TokenFlags]::Keyword)) {
            $end = $token.Extent.EndOffset
            $len = $end - $cursor
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                $cursor,
                $len,
                $quote + $line.SubString($cursor, $len) + $quote
            )
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($end + 2)
            return
        }
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
}

# 5.2 Smart opening parentheses/brackets/braces: auto-pair or wrap selection
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

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($selectionStart -ne -1) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
            $selectionStart,
            $selectionLength,
            $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar
        )
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        return
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($key.KeyChar + $closeChar)
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
}

# 5.3 Smart closing parentheses/brackets/braces: skip if character is ahead
Set-PSReadLineKeyHandler -Key ')', ']', '}' `
                         -BriefDescription SmartCloseParen `
                         -LongDescription "Skip closing parenthesis/bracket/brace if present" `
                         -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($cursor -lt $line.Length -and $line[$cursor] -eq $key.KeyChar) {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($key.KeyChar)
    }
}

# 5.4 Smart backspace: delete pair when cursor is between empty quotes or parens
Set-PSReadLineKeyHandler -Key Backspace `
                         -BriefDescription SmartBackspace `
                         -LongDescription "Delete pair if inside empty quotes or parens" `
                         -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

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
    [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
}

# ------------------------------------------------------------------------------
# 6. Predictive Suggestions & Keybindings (RightArrow: line, Ctrl+RightArrow: word)
# ------------------------------------------------------------------------------
try {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
    Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction SilentlyContinue
} catch {
    # Ignore errors in non-interactive/redirected environments
}

# 6.1 RightArrow: Move cursor right inline, or accept full suggestion at EOL
Set-PSReadLineKeyHandler -Key RightArrow `
                         -BriefDescription ForwardCharOrAcceptSuggestion `
                         -LongDescription "Move cursor right, or accept entire suggestion if at end of line" `
                         -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($cursor -lt $line.Length) {
        [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar($key, $arg)
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptSuggestion($key, $arg)
    }
}

# 6.2 Ctrl+RightArrow: Move token forward inline, or accept next suggestion word at EOL
Set-PSReadLineKeyHandler -Key Ctrl+RightArrow `
                         -BriefDescription ShellForwardWordOrAcceptNextWord `
                         -LongDescription "Move forward token, or accept next suggestion word if at end of line" `
                         -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($cursor -lt $line.Length) {
        [Microsoft.PowerShell.PSConsoleReadLine]::ShellForwardWord($key, $arg)
    } else {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord($key, $arg)
    }
}

# ------------------------------------------------------------------------------
# 7. Auto-navigate from System32 to ~ (User Home Directory)
# ------------------------------------------------------------------------------
if ($PWD.Path -eq "$env:windir\System32" -or $PWD.Path -eq "$env:windir\SysWOW64") {
    Set-Location ~
}

# ------------------------------------------------------------------------------
# 8. Windows Terminal Shell Integration: Path Reporting (OSC 9;9)
# ------------------------------------------------------------------------------
function prompt {
    $loc = $($ExecutionContext.SessionState.Path.CurrentLocation)
    $esc = [char]27
    $bel = [char]7
    Write-Host -NoNewline "$esc]9;9;`"$loc`"$bel"
    "PS $loc$('>' * ($nestedPromptLevel + 1)) "
}
