# WSL `E_ACCESSDENIED` Investigation

Date: 2026-03-30
Host user: `<host>\<your-windows-user>`
Target distro: `Ubuntu`
Target VHDX: `D:\WSL\Ubuntu\ext4.vhdx`

Wall-clock times in the captured output are redacted. The placeholders are
stable, so the evidence they carry survives: the same `<t-...>` token means the
same instant everywhere it appears, and the pre- / post-repair `dir /q` blocks
below are identical in their time columns because the repair did not touch
mtimes. Durations between events are stated in prose where they matter.

## Symptom

Cold-boot attempt from an elevated PowerShell:

```text
wsl -l -v
  NAME      STATE           VERSION
* Ubuntu    Stopped         2

wsl -d Ubuntu -- whoami
Failed to attach disk 'D:\WSL\Ubuntu\ext4.vhdx' to WSL2: Access is denied.
Error code: Wsl/Service/CreateInstance/MountDisk/HCS/E_ACCESSDENIED
```

## Read-only findings

### 1. Registration and basic WSL state are intact

- `wsl -l -v` can enumerate `Ubuntu`
- `wsl --status` is normal
- `WSLService`, `vmcompute`, and `hns` are running

This means the distro registration is not broken. The failure occurs during disk attach, not during distro lookup.

### 2. The persistent owner / base ACL are not the immediate problem anymore

At the time of the cold-boot failure:

```text
D:\WSL owner                : BUILTIN\Administrators
D:\WSL\Ubuntu owner         : <your-windows-user>
D:\WSL\Ubuntu\ext4.vhdx owner : <your-windows-user>
```

Relevant ACL snapshot while WSL was stopped:

```text
D:\WSL\Ubuntu <your-windows-user>\:(OI)(CI)(F)
              BUILTIN\Administrators:(I)(F)
              NT AUTHORITY\SYSTEM:(I)(F)
              NT AUTHORITY\Authenticated Users:(I)(M)
              BUILTIN\Users:(I)(RX)
```

```text
D:\WSL\Ubuntu\ext4.vhdx S-1-5-83-1-<vm-1>:(F)
                        S-1-5-83-1-<vm-4>:(F)
                        S-1-5-83-1-<vm-2>:(F)
                        <your-windows-user>\:(I)(F)
                        BUILTIN\Administrators:(I)(F)
                        NT AUTHORITY\SYSTEM:(I)(F)
                        NT AUTHORITY\Authenticated Users:(I)(M)
                        BUILTIN\Users:(I)(RX)
```

So the prior obvious failure mode ("wrong owner, no user access") is already fixed.

### 3. The failure is correlated with missing runtime VM-specific ACEs

After a later read-only retry succeeded, the same VHDX ACL changed to:

```text
D:\WSL\Ubuntu\ext4.vhdx S-1-15-3-1024-2268835264-3721307629-241982045-173645152-1490879176-104643441-2915960892-1612460704:(F)
                        NT VIRTUAL MACHINE\<vm-3>:(F)
                        S-1-5-83-1-<vm-1>:(F)
                        S-1-5-83-1-<vm-4>:(F)
                        S-1-5-83-1-<vm-2>:(F)
                        <your-windows-user>\:(I)(F)
                        BUILTIN\Administrators:(I)(F)
                        NT AUTHORITY\SYSTEM:(I)(F)
                        NT AUTHORITY\Authenticated Users:(I)(M)
                        BUILTIN\Users:(I)(RX)
```

This is the strongest local evidence in this investigation:

- In the failing stopped state, the VHDX does **not** have the extra `S-1-15-3-...` ACE or the current `NT VIRTUAL MACHINE\...` ACE.
- After a successful attach/start, those ACEs appear immediately.
- The VHDX `LastWriteTime` also advances on successful attach.

This strongly suggests the intermittent failure happens during the runtime ACL-stamping / VM attach path, not because the persisted user/admin/system ACL is obviously wrong.

### 4. The parent folder chain is inconsistent

Directory owners under `D:\WSL` are split:

```text
D:\WSL         -> BUILTIN\Administrators
D:\WSL\backup  -> BUILTIN\Administrators
D:\WSL\Ubuntu  -> <your-windows-user>
D:\WSL\Ubuntu\ext4.vhdx -> <your-windows-user>
```

`cmd /c dir /q D:\WSL`:

```text
<t-created>      <DIR>          BUILTIN\Administrators .
<t-backup>       <DIR>          BUILTIN\Administrators backup
<t-created>      <DIR>          <your-windows-user>\   Ubuntu
```

This mixed ownership does not prove causality by itself, but it is the only clear persistent asymmetry left in the storage path.

### 5. Hyper-V / HCS evidence

When WSL starts successfully, Hyper-V Compute Operational logs show a successful attach of the moved VHDX:

```text
TimeCreated : <t-success>
Id          : 2007
Message     : [<activity-id-1>] Modify compute system, settings
              ... "Path":"D:\\WSL\\Ubuntu\\ext4.vhdx" ...
              result 0x00000000
```

At the failure timestamp window, the inspected Compute / Worker channels did not emit a direct human-readable `Access is denied` line, but they did show that the utility VM lifecycle around that VM ID was abnormal and short-lived.

## Assessment

Most likely root cause:

1. The distro is now on a custom `D:\WSL` tree rather than the default per-user WSL location.
2. The base owner / ACL on `D:\WSL\Ubuntu` and the VHDX are acceptable, but the parent path `D:\WSL` remains admin-owned.
3. WSL / HCS adds VM-specific ACEs to the VHDX dynamically during successful startup.
4. On cold boot, that runtime attach / ACL-stamping path is intermittently failing before the full healthy ACE set is present.

In short:

- This does **not** look like a permanently broken distro registration.
- This does **not** look like a simple "user lost Full Control" case anymore.
- It **does** look like an intermittent permission-context problem on the moved storage path.

## Repair strategy chosen

Normalize the ownership / access model of the whole `D:\WSL` subtree so the parent path and the distro path are no longer split between `Administrators` and `<your-windows-user>`.

Planned minimal fix:

- Make `D:\WSL` owned by `<your-windows-user>`
- Give `<your-windows-user>` explicit full control on `D:\WSL` recursively
- Preserve existing `SYSTEM` / `Administrators` access
- Re-test WSL startup

## Repair applied

Applied:

```text
wsl --shutdown
icacls D:\WSL /setowner <your-windows-user> /T /C
icacls D:\WSL /grant <your-windows-user>:(OI)(CI)F /T /C
Restart-Service WSLService
```

Post-repair owner chain:

```text
D:\WSL         -> <your-windows-user>
D:\WSL\backup  -> <your-windows-user>
D:\WSL\Ubuntu  -> <your-windows-user>
D:\WSL\Ubuntu\ext4.vhdx -> <your-windows-user>
```

Post-repair `cmd /c dir /q D:\WSL`:

```text
<t-created>      <DIR>          <your-windows-user>\   .
<t-backup>       <DIR>          <your-windows-user>\   backup
<t-created>      <DIR>          <your-windows-user>\   Ubuntu
```

## Validation

After the repair:

1. `wsl -d Ubuntu -- whoami` succeeded
2. `wsl --shutdown` followed by `wsl -d Ubuntu -- whoami` succeeded again
3. Repeating that cold-start style check a second time also succeeded

Validation output:

```text
<your-linux-user>
<your-linux-user>
```

Current result:

- The intermittent cold-start `MountDisk/HCS/E_ACCESSDENIED` issue is no longer reproducing in post-repair testing.

## Addendum: later recurrence on the same day

After the ownership normalization above, the symptom recurred again without a Windows reboot. That new evidence changes the assessment materially.

### 6. Hyper-V successfully attaches the moved VHDX even when the user-facing message says `MountDisk ... E_ACCESSDENIED`

At the later failure window -- about 15 minutes after the successful attach above -- `Microsoft-Windows-Hyper-V-Compute-Operational` logged:

```text
TimeCreated : <t-failure>
Id          : 2007
Message     : [<activity-id-2>] Modify compute system, settings
              ... "Path":"D:\\WSL\\Ubuntu\\ext4.vhdx" ...
              result 0x00000000
```

The same sequence also showed:

```text
Create compute system, result 0xC0370103
Start compute system,  result 0xC0370103
```

`certutil -error 0xC0370103` resolves that code to:

```text
The call to start an asynchronous operation succeeded and the operation is performed in the background.
```

So this specific `0xC0370103` is **not** a hard failure. The local evidence now shows:

- WSL / HCS can create the compute system
- WSL / HCS can start the compute system
- WSL / HCS can attach `D:\WSL\Ubuntu\ext4.vhdx`

This means the screen error text is at least incomplete, and the root cause is not simply "the VHDX cannot be opened because of a bad ACL".

### 7. The host is using Clash for Windows plus mirrored networking

Current host state:

```text
HKCU Internet Settings ProxyEnable = 1
HKCU Internet Settings ProxyServer = 127.0.0.1:7890
WinHTTP proxy                      = 127.0.0.1:7890
.wslconfig                         = autoProxy=true, networkingMode=mirrored, dnsTunneling=true
```

Observed running processes and listeners:

```text
Clash for Windows.exe       running
clash-core-service.exe      running
clash-win64.exe             listening on 127.0.0.1:7890
```

WSL guest checks from Ubuntu while running:

```text
127.0.0.1:7890   -> connect-ok
10.255.255.254   -> connect-fail (Connection refused)
curl http://example.com -> HTTP/1.1 200 OK
```

So the Windows proxy itself is not currently dangling, but the machine is using a combination that is more complex than stock WSL networking:

- `networkingMode=mirrored`
- `autoProxy=true`
- local loopback proxy on `127.0.0.1:7890`

### 8. Repeated `shutdown -> start` testing is currently stable

Post-recurrence validation:

```text
12 consecutive cycles of:
  wsl --shutdown
  wsl -d Ubuntu -- whoami
```

All 12 attempts returned:

```text
<your-linux-user>
```

So the problem is intermittent and not reproducible on demand with simple start/stop loops.

## Revised assessment

The earlier "mixed ownership on `D:\WSL` is the main cause" assessment is not sufficient anymore.

What is now supported by the evidence:

1. The moved VHDX path and base ACL are good enough for successful attach.
2. Hyper-V / HCS can attach `D:\WSL\Ubuntu\ext4.vhdx` and start the utility VM.
3. The issue is intermittent and survives ownership normalization.
4. The machine is using mirrored networking together with Windows proxy mirroring and a local Clash loopback proxy.

The most defensible current hypothesis is:

- the recurring startup issue is in the WSL runtime path after compute-system creation begins,
- and the `autoProxy + mirrored networking + local loopback proxy` combination is the most suspicious remaining moving part.

## Revised repair direction

Preferred next minimal change:

- keep `networkingMode=mirrored`
- disable `autoProxy`

Rationale:

- it removes one WSL startup-time integration layer,
- it keeps mirrored localhost reachability, so `127.0.0.1:7890` can still be used manually from Ubuntu,
- and it is a smaller behavioral change than switching all of WSL back to default NAT immediately.

## Revised repair applied

Changed host `.wslconfig`:

```text
[wsl2]
autoProxy=false
networkingMode=mirrored
dnsTunneling=true
memory=10GB
processors=8
swap=4GB
```

Applied with:

```text
wsl --shutdown
```

## Revised validation

After disabling `autoProxy`:

1. `wsl -d Ubuntu -- whoami` succeeded
2. Ubuntu could still connect to `127.0.0.1:7890`
3. 10 consecutive cycles of:

```text
wsl --shutdown
wsl -d Ubuntu -- whoami
```

all succeeded and returned `<your-linux-user>`

## Remaining uncertainty

Even after `autoProxy=false`, the Ubuntu journal still shows:

```text
WSL (...) ERROR: CheckConnection: getaddrinfo() failed: -5
```

So:

- disabling `autoProxy` improves the configuration by removing one risky integration layer,
- but it does **not** prove that `CheckConnection` was exclusively caused by proxy mirroring,
- and the exact internal WSL component behind that log line remains unconfirmed.

## Practical current state

Current state is better described as:

- startup is presently stable in repeated testing,
- the moved VHDX path is healthy,
- `127.0.0.1:7890` is still reachable from Ubuntu,
- if the intermittent startup failure returns again, the next strongest mitigation would be to disable `networkingMode=mirrored` as well and fall back to default WSL NAT networking.
