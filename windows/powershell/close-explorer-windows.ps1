# Close every open File Explorer window, leaving the desktop and taskbar alone.
#
# Why the Shell.Application COM object rather than `Stop-Process explorer`:
# explorer.exe is one process serving BOTH the folder windows and the desktop
# shell (taskbar, Start, tray). Killing it takes the whole shell down and
# Windows has to respawn it -- the screen flashes, tray icons re-register, and
# anything that hooked the shell may not come back. Shell.Application enumerates
# just the open windows and asks each one to Quit, so the desktop is untouched.
#
# The FullName check is what separates folder windows from Internet Explorer /
# Edge legacy windows, which the same collection also returns.
#
# Usage:  pwsh -NoProfile -File close-explorer-windows.ps1
# From WSL, see ../../agent/skills/wsl-windows-command/scripts/run-pwsh.sh
$shell = New-Object -ComObject "Shell.Application"
$windows = $shell.Windows()

foreach ($w in $windows) {
    if ($w -and $w.FullName -and $w.FullName.ToLower().EndsWith("explorer.exe")) {
        try {
            $w.Quit()
        } catch {
        }
    }
}