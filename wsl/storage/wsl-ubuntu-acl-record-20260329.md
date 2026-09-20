# WSL Ubuntu ACL Record

Timestamp: <capture-time>

Wall-clock times are redacted. `<t-created>` and `<t-last-write>` are stable
tokens: the VHDX was created at one instant and last written at a later one,
which is the only thing these fields are quoted for.

## Launch Context

Current Windows user:

```text
USER INFORMATION
----------------

User Name SID
========= =============================================
<host>\<your-windows-user>       S-1-5-21-XXXXXXXXX-XXXXXXXXX-XXXXXXXXX-1001
```

## WSL Status

```text
Default distribution: Ubuntu
Default version: 2
```

`wsl -l -v` at capture time:

```text
NAME      STATE    VERSION
* Ubuntu  Running  2
```

## WSL Registration

Relevant registry values from `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss`:

```text
DistributionName    REG_SZ    Ubuntu
Version             REG_DWORD 0x2
BasePath            REG_SZ    D:\WSL\Ubuntu
VhdFileName         REG_SZ    ext4.vhdx
DefaultUid          REG_DWORD 0x3e8
Flavor              REG_SZ    ubuntu
OsVersion           REG_SZ    24.04
```

## VHDX Metadata

```text
FullName      : D:\WSL\Ubuntu\ext4.vhdx
Length        : 22783459328
CreationTime  : <t-created>
LastWriteTime : <t-last-write>
Attributes    : Archive
```

## Owners

PowerShell `Get-Acl(...).Owner`:

```text
D:\WSL\Ubuntu owner           : O:S-1-5-21-XXXXXXXXX-XXXXXXXXX-XXXXXXXXX
D:\WSL\Ubuntu\ext4.vhdx owner : O:S-1-5-21-XXXXXXXXX-XXXXXXXXX-XXXXXXXXX
```

`cmd /c dir /q D:\WSL\Ubuntu` shows:

```text
<t-created>      <DIR>          <your-windows-user>\   .
<t-created>      <DIR>          BUILTIN\Administrators ..
<t-last-write>   22,783,459,328 <your-windows-user>\   ext4.vhdx
```

## ACL Snapshot

`icacls D:\WSL`:

```text
D:\WSL BUILTIN\Administrators:(I)(F)
       BUILTIN\Administrators:(I)(OI)(CI)(IO)(F)
       NT AUTHORITY\SYSTEM:(I)(F)
       NT AUTHORITY\SYSTEM:(I)(OI)(CI)(IO)(F)
       NT AUTHORITY\Authenticated Users:(I)(M)
       NT AUTHORITY\Authenticated Users:(I)(OI)(CI)(IO)(M)
       BUILTIN\Users:(I)(RX)
       BUILTIN\Users:(I)(OI)(CI)(IO)(GR,GE)
```

`icacls D:\WSL\Ubuntu`:

```text
D:\WSL\Ubuntu <your-windows-user>\:(OI)(CI)(F)
              BUILTIN\Administrators:(I)(F)
              BUILTIN\Administrators:(I)(OI)(CI)(IO)(F)
              NT AUTHORITY\SYSTEM:(I)(F)
              NT AUTHORITY\SYSTEM:(I)(OI)(CI)(IO)(F)
              NT AUTHORITY\Authenticated Users:(I)(M)
              NT AUTHORITY\Authenticated Users:(I)(OI)(CI)(IO)(M)
              BUILTIN\Users:(I)(RX)
              BUILTIN\Users:(I)(OI)(CI)(IO)(GR,GE)
```

`icacls D:\WSL\Ubuntu\ext4.vhdx`:

```text
D:\WSL\Ubuntu\ext4.vhdx NT VIRTUAL MACHINE\<vm-1>:(F)
                        S-1-15-3-1024-2268835264-3721307629-241982045-173645152-1490879176-104643441-2915960892-1612460704:(F)
                        S-1-5-83-1-<vm-2>:(F)
                        <your-windows-user>\:(I)(F)
                        BUILTIN\Administrators:(I)(F)
                        NT AUTHORITY\SYSTEM:(I)(F)
                        NT AUTHORITY\Authenticated Users:(I)(M)
                        BUILTIN\Users:(I)(RX)
```

## Notes

- The moved distro is healthy when `BasePath` is `D:\WSL\Ubuntu`, `wsl -d Ubuntu -- whoami` returns `<your-linux-user>`, and the VHDX ACL contains the extra `NT VIRTUAL MACHINE\...` full-control entry.
- If `MountDisk/HCS/E_ACCESSDENIED` appears again, compare the current `icacls D:\WSL\Ubuntu\ext4.vhdx` output against this snapshot first.
