# Windows Registry Management from WSL

The Windows registry can be queried, modified, and exported from WSL via `reg.exe` or declarative `.reg` files. Privilege rules follow the target hive: `HKCU` requires no elevation; `HKLM` requires elevated Windows privileges.

Always capture both stdout and stderr (`2>&1`), as `reg.exe` outputs error diagnostics (such as key not found or access denied) to stderr.

---

## 1. The `/reg:64` Redirection Gotcha (Critical)

### Symptom
Listing a parent registry key succeeds and displays its subkeys, but querying a specific subkey directly returns:
```text
ERROR: The system was unable to find the specified registry key or value.
```

### Cause: WOW64 Registry Redirection
When `reg.exe` is launched via WSL interop, 64-bit Windows may resolve `HKLM\Software\...` against the 32-bit (`Wow6432Node`) view where the subkey does not exist.

### Solution
Always append `/reg:64` to force the native 64-bit view:

```bash
REG="/mnt/c/Windows/System32/reg.exe"

# Query specific subkey with 64-bit view:
"$REG" query "HKLM\Software\Classes\Directory\Background\shell\PowerShell" /reg:64 < /dev/null

# Recursively dump a subtree:
"$REG" query "HKLM\Software\Classes\Directory\Background\shell" /s /reg:64 < /dev/null
```

> **Rule of Thumb**: If a key "should" exist but returns not found, always test with `/reg:64` before concluding it is absent.

---

## 2. Reading and Writing Registry Values

```bash
REG="/mnt/c/Windows/System32/reg.exe"

# 1. Default (unnamed) value:
"$REG" add "HKCU\Software\Classes\Directory\Background\shell\Demo" /ve /d "My Custom Action" /f < /dev/null

# 2. Named string value (REG_SZ):
"$REG" add "HKCU\Software\Classes\Directory\Background\shell\Demo" /v Icon /t REG_SZ /d "C:\\Windows\\System32\\wsl.exe" /f < /dev/null

# 3. Environment-variable string (REG_EXPAND_SZ):
# Important: Use REG_EXPAND_SZ so %LocalAppData% expands at runtime in Windows
"$REG" add "HKCU\Software\Classes\Directory\Background\shell\Demo" /v Icon /t REG_EXPAND_SZ /d "%LocalAppData%\\Programs\\app\\app.exe" /f < /dev/null

# 4. Delete a key and all subkeys:
"$REG" delete "HKCU\Software\Classes\Directory\Background\shell\Demo" /f < /dev/null
```

### Scope Selection: `HKCR` vs `HKCU` / `HKLM`
`HKCR` (`HKEY_CLASSES_ROOT`) is a merged view of `HKLM\Software\Classes` and `HKCU\Software\Classes`.
* When **reading**, `HKCR` is convenient.
* When **writing**, always target the explicit hive (`HKCU\Software\Classes` for current user, `HKLM\Software\Classes` for machine-wide) instead of writing to `HKCR`.

---

## 3. Declarative `.reg` Files

For shareable, repeatable registry changes, generate a `.reg` file and import it.

### Two Strict Rules for `.reg` Files

1. **UTF-16 LE Encoding for Non-ASCII Text**:
   If the `.reg` file contains non-ASCII characters (e.g., Chinese labels, Japanese, accents), it **must be saved as UTF-16 LE with BOM**. If saved as UTF-8, Windows Registry Editor will import garbled text. Pure ASCII files can be saved as standard UTF-8/ASCII.

   ```python
   # Python helper to write a UTF-16 LE .reg file.
   #
   # The menu label is kept in one variable, spelled with \u escapes so this
   # source file stays pure ASCII while the emitted .reg still carries real
   # non-ASCII text -- precisely the case that forces UTF-16 LE. Replace it
   # with a literal string if your toolchain is fine with non-ASCII sources.
   label = "\u5728\u6b64\u5904\u6253\u5f00 WSL"   # "open here with WSL", zh-CN

   content = f"""Windows Registry Editor Version 5.00

   [HKEY_CURRENT_USER\\Software\\Classes\\Directory\\Background\\shell\\OpenInWSL]
   @="{label}"
   "Icon"="C:\\\\Windows\\\\System32\\\\wsl.exe"
   """
   with open("custom_menu.reg", "w", encoding="utf-16-le") as f:
       f.write("\ufeff" + content)   # BOM
   ```

2. **Escaping Rules**:
   - Double all backslashes in paths: `C:\\Windows\\System32\\wsl.exe`
   - Double quotes inside values must be escaped: `\"`
   - Default value is represented as `@="..."`
   - A leading minus sign (`-`) deletes a key: `[-HKEY_CURRENT_USER\Software\...\OldKey]`

### Importing `.reg` Files
```bash
"/mnt/c/Windows/regedit.exe" /s "C:\\path\\to\\file.reg" < /dev/null
```

---

## 4. Applying Registry Changes (Restarting Explorer)

Context menu and shell file-association edits often require Windows Explorer to reload:

```bash
"/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Stop-Process -Name explorer -Force" < /dev/null
```

> **Warning**: Explorer will automatically restart, but any open File Explorer windows will be closed. Warn the user before running this command.
