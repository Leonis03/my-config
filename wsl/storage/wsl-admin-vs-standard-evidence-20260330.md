# WSL Admin vs Standard Evidence

Date: 2026-03-30
Host user: `<host>\<your-windows-user>`
Target distro: `Ubuntu`
Target VHDX: `D:\WSL\Ubuntu\ext4.vhdx`

## Current host config

Current [`.wslconfig`](/C:/Users/<your-windows-user>/.wslconfig):

```ini
[wsl2]
autoProxy=false
# networkingMode=mirrored
dnsTunneling=true

memory=10GB
processors=8
swap=4GB
```

This matters because it removes the earlier "mirrored networking / autoProxy" hypothesis from the critical path. The issue still reproduces with both of those effectively disabled.

## 1. Unelevated reproduction

An actual medium-integrity PowerShell was launched via a scheduled task running as the same user with `RunLevel Limited`.

Captured token evidence:

```text
IS_ADMIN = False
Mandatory Label = Medium Mandatory Level
BUILTIN\Administrators = Group used for deny only
```

That unelevated script ran:

```powershell
wsl --shutdown
wsl -d Ubuntu -- whoami
```

Result:

```text
WSL_EXIT_CODE = -1
Failed to attach disk 'D:\WSL\Ubuntu\ext4.vhdx' to WSL2: Access is denied.
Error code: Wsl/Service/CreateInstance/MountDisk/HCS/E_ACCESSDENIED
```

ACL of `ext4.vhdx` in the failed unelevated state:

```text
D:\WSL\Ubuntu\ext4.vhdx
  S-1-5-83-1-<vm-3>:(F)
  S-1-5-83-1-<vm-1>:(F)
  S-1-5-83-1-<vm-4>:(F)
  S-1-5-83-1-<vm-2>:(F)
  <your-windows-user>:(I)(F)
  BUILTIN\Administrators:(I)(F)
  NT AUTHORITY\SYSTEM:(I)(F)
  NT AUTHORITY\Authenticated Users:(I)(M)
  BUILTIN\Users:(I)(RX)
```

Important negative evidence:

- no `S-1-15-3-1024-...` ACE
- no `NT VIRTUAL MACHINE\...` ACE

## 2. Elevated success in the same machine state

Immediately after that failed unelevated attempt, an elevated PowerShell ran:

```powershell
wsl --shutdown
wsl -d Ubuntu -- whoami
```

Result:

```text
ExitCode=0
<your-linux-user>
```

ACL of `ext4.vhdx` in the successful elevated state:

```text
D:\WSL\Ubuntu\ext4.vhdx
  S-1-15-3-1024-2268835264-3721307629-241982045-173645152-1490879176-104643441-2915960892-1612460704:(F)
  NT VIRTUAL MACHINE\<vm-2>:(F)
  S-1-5-83-1-<vm-3>:(F)
  S-1-5-83-1-<vm-1>:(F)
  S-1-5-83-1-<vm-4>:(F)
  S-1-5-83-1-<vm-2>:(F)
  <your-windows-user>:(I)(F)
  BUILTIN\Administrators:(I)(F)
  NT AUTHORITY\SYSTEM:(I)(F)
  NT AUTHORITY\Authenticated Users:(I)(M)
  BUILTIN\Users:(I)(RX)
```

Important positive evidence:

- the successful elevated start adds back `S-1-15-3-1024-...`
- the successful elevated start adds back a fresh `NT VIRTUAL MACHINE\<vm-2>...`

## 3. Hyper-V / HCS evidence for the elevated success

`Microsoft-Windows-Hyper-V-Compute-Operational` for the successful elevated start:

```text
Modify compute system ... "Path":"D:\\WSL\\Ubuntu\\ext4.vhdx" ... result 0x00000000
Create compute system, result 0xC0370103
Start compute system,  result 0xC0370103
```

`0xC0370103` was previously resolved locally via `certutil -error` to:

```text
The call to start an asynchronous operation succeeded and the operation is performed in the background.
```

`Microsoft-Windows-Hyper-V-Worker-Admin` for that same start showed the VM and its devices starting successfully.

## 4. Conclusion

This comparison narrows the problem substantially.

What is now directly supported by local evidence:

1. With the same user account, same distro, same VHDX, and same host config, an unelevated token fails after `wsl --shutdown`.
2. An elevated token succeeds immediately afterward.
3. The successful elevated start causes `ext4.vhdx` to gain VM-specific runtime ACEs that are absent in the failed unelevated state.
4. This still happens even with `autoProxy=false` and `networkingMode=mirrored` disabled.

The best current diagnosis is:

- this is not primarily a networking or proxy issue,
- and it is not a permanently broken static ACL on the file,
- it is a Windows-side runtime attach / ACL-stamping problem where the moved WSL VHDX can be initialized successfully only when the first post-shutdown start is triggered from an elevated token.

## Practical implication

Current reliable workaround:

```powershell
wsl --shutdown
wsl -d Ubuntu -- whoami
```

must be executed from an elevated PowerShell when the distro is in the bad post-shutdown state.
