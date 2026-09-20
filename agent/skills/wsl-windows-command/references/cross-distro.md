# Cross-Distro Work in WSL

Driving one WSL distro from another. **Commands** have to go through the Windows-side interop
bridge. **Files** do not: `/mnt/wsl` is a tmpfs shared by every WSL2 distro, and a bind mount
into it is a direct Linux-to-Linux path, measured 20-35x faster than routing reads through
`\\wsl.localhost` (section 2).

Measurements and "verified" claims on this page were taken on WSL 2.7.14.0, kernel
6.18.33.2, with Ubuntu 24.04.4 and Fedora 44 both running (2026-09-20). The two items that
were **not** reproduced locally are labelled as such in place.

---

## 1. Running a Command in Another Distro

```bash
cd /mnt/c && /mnt/c/Windows/System32/wsl.exe -d Fedora -u root -e sh -c 'cat /etc/os-release' \
  < /dev/null 2>&1 | tr -d '\0\r'
```

Every part of that line is load-bearing:

| Fragment | Why |
| :--- | :--- |
| `cd /mnt/c` | Harmless insurance, **not required for `wsl.exe`**. Verified: `wsl.exe` runs fine with a WSL cwd. Only `cmd.exe` refuses a UNC working directory (see Golden Rule 4 in SKILL.md). Keep it if a pipeline mixes `wsl.exe` and `cmd.exe`; drop it otherwise |
| absolute path to `wsl.exe` | bare `wsl.exe` is not on PATH in non-interactive shells |
| `-d <distro>` | target distro; omit and you re-enter the default one |
| `-u root` | the target distro's default user may not have passwordless sudo |
| `-e <cmd>` | run directly, skipping the login shell (faster, no profile side effects) |
| `< /dev/null` | the interop bridge blocks on stdin |
| `tr -d '\0\r'` | `wsl.exe` emits UTF-16 LE; without this you get `F e d o r a` |

Prefer `-e sh -c '...'` with **single** quotes over nesting double quotes. For anything
longer than one line, pipe a heredoc into `tee` (see below) and run the file.

### Know which distro you are in before you pass `-d`

`wsl.exe -l -v` marks the **default** distro with `*`, not the one you are running in. Read
that star as "you are here" and `-d <name>` silently re-enters the distro you are already in.
Nothing errors. A test that writes a marker "into the other distro" then reads it back passes
perfectly -- it is your own file. That happened while writing this page and burned a full
round of results; the tell only showed up in `stat -c %d`, where the "two" distros had the
same device number.

The authoritative answer is the variable WSL sets in every distro, and it survives
`-e sh -c` through interop:

```bash
echo "$WSL_DISTRO_NAME"
```

Two independent cross-checks, useful when reading back a transcript that did not print it:
the admin group (`wheel` on Fedora/RHEL, `sudo` on Debian/Ubuntu) via `id -Gn`, and
`. /etc/os-release; echo "$NAME"`.

---

## 2. Sharing Filesystems: `/mnt/wsl` Is the Answer, Not `\\wsl.localhost`

Distros share the VM but not their mount namespaces: another distro's mounts are absent from
`/proc/self/mountinfo` and its PIDs are invisible. The one exception is `/mnt/wsl`, a tmpfs
mounted **shared** into every WSL2 distro (`shared:1` in `mountinfo`). Any bind mount whose
**target** sits under `/mnt/wsl` propagates to every other distro -- including ones started
later. This shipped in Windows build 19041 and is how Docker Desktop has always done it;
[microsoft/WSL#5177](https://github.com/microsoft/WSL/issues/5177) was closed `/fixed 19041`
on exactly this.

From the distro that owns the files:

```bash
sudo mkdir -p /mnt/wsl/Ubuntu
sudo mount --bind / /mnt/wsl/Ubuntu     # source is free, the TARGET must be under /mnt/wsl
```

Or drive it from the other side, which is the usual shape in a script:

```bash
cd /mnt/c && /mnt/c/Windows/System32/wsl.exe -d Ubuntu -u root -e sh -c \
  'mkdir -p /mnt/wsl/Ubuntu && mount --bind / /mnt/wsl/Ubuntu' < /dev/null 2>&1 | tr -d '\0\r'
```

`-u root` is not optional. Without it `mount` fails with a misleading
`mount point does not exist`.

Verified end to end: Fedora reads `/mnt/wsl/Ubuntu/etc/os-release` as `Ubuntu 24.04.4 LTS`,
Ubuntu reads `/mnt/wsl/Fedora/etc/os-release` as `Fedora Linux`, and both write into the
other's `/home/<user>` as the **non-root** user. `stat -c %d` confirms two distinct devices, and
`lsblk` shows each distro's VHDX as its own disk (`sdd` -> `/mnt/wsl/Ubuntu`,
`sde` -> `/mnt/wsl/Fedora` and `/`).

### Rules and traps

| Fact | Detail |
| :--- | :--- |
| Target must be under `/mnt/wsl` | A bind anywhere else stays private to that distro's namespace. This is the whole mechanism, not a convention |
| WSL2 only | A WSL1 distro has no shared `/mnt/wsl`. For those, SSH/rsync or a tar relay through `/mnt/c` is the only option |
| Permissions are raw UIDs | Non-root access works only if the UIDs line up. Here both users are `1000`, so it just worked; separate installs can disagree (a documented case has `1000` vs `1002`), and then you need `-u root` or a `chown` |
| `umount` propagates too | Unmounting from either side removes it everywhere -- the second `umount` reports `not mounted` |
| Mount points are tmpfs | `wsl --shutdown` drops the whole VM and with it every `/mnt/wsl` mount point. Re-create at boot from `/etc/fstab` plus a `[boot] command` in `wsl.conf`, or from a shell profile. **Not tested here** -- `--shutdown` would kill the session doing the testing |
| Ordering is the real cost | A distro that looks at `/mnt/wsl` before the owner has bound anything simply sees nothing, with no error. The converse is fine and was verified: a mount created while the other distro was `Stopped` is present when it cold-starts |
| `automount root = /` breaks it silently | That `wsl.conf` setting relocates `/mnt/wsl`, so the recipe appears to run and nothing shows up in the other distro. **Not tested here** -- reported in [#5177](https://github.com/microsoft/WSL/issues/5177); reproducing it means mutating another distro's `wsl.conf` |
| [microsoft/WSL#6196](https://github.com/microsoft/WSL/issues/6196) does **not** reproduce | The 2020 report that binding `/mnt/c` into `/mnt/wsl/c` breaks other distros' `/mnt/c` was retested on 2.7.14: the cold-started distro got its own 9p mount and both `/mnt/c` and `/mnt/wsl/c` worked |

### Why not `\\wsl.localhost`

`\\wsl.localhost\<distro>\...` is a **Windows** UNC path served by the 9p provider on the
Windows side. It is reachable from a Windows process, never from the Linux side of another
distro. Walking up through `/mnt/c` to reach it fails:

```bash
ls /mnt/c/Windows/System32/../../../../wsl.localhost/Fedora/home/<user>
# ls: cannot access ...: No such file or directory
```

So it always costs a Windows round trip, and 9p makes that expensive. Same workload
(Ubuntu's `/usr/include`, 2313 files, 21.6 MB), caches dropped before every run, identical
byte counts out of both:

| Operation | via `/mnt/wsl` bind | via `\\wsl.localhost` + `powershell.exe` |
| :--- | ---: | ---: |
| Traverse, count files | 0.037 s | 1.30 s |
| Read every byte | 0.97 s | 22.5 s |

`powershell.exe` itself starts in 0.15 s here, so startup is not what you are paying for --
it is 9p per-file latency, and it scales with file count.

Keep the UNC route for the case it is actually good at: touching a distro you do not want to
start, or reading from code that is already a Windows process.

```bash
cd /mnt/c && "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile \
  -ExecutionPolicy Bypass -Command "Get-ChildItem '\\\\wsl.localhost\\Fedora\\home'" \
  < /dev/null 2>&1 | tr -d '\0\r'
```

---

## 3. Moving Files Between Distros

For a bulk copy, bind-mount per section 2 and use plain `cp`. For a one-off file, or when you
do not want to leave a mount behind, stream it through interop:

```bash
# Push a file from here into Fedora
cat ./notes.md | (cd /mnt/c && /mnt/c/Windows/System32/wsl.exe -d Fedora -u <user> -e tee /home/<user>/notes.md > /dev/null)

# Pull a file out of Fedora
cd /mnt/c && /mnt/c/Windows/System32/wsl.exe -d Fedora -u <user> -e cat /home/<user>/notes.md \
  < /dev/null 2>&1 | tr -d '\r' > ./notes.md
```

Always verify afterwards -- a truncated transfer is silent:

```bash
wc -l ./notes.md
cd /mnt/c && /mnt/c/Windows/System32/wsl.exe -d Fedora -u <user> -e wc -l /home/<user>/notes.md < /dev/null 2>&1 | tr -d '\0\r'
```

`/mnt/c` is a workable relay too, but only if it is mounted `rw` in **both** distros -- a
hardened setup may mount it `ro` (see [hardened-mounts.md](hardened-mounts.md)).

---

## 4. `binfmt_misc` Is Global: Another Distro Breaks Your Interop

**This is the single most surprising fact about multi-distro WSL.**

All WSL distros share one kernel, and `binfmt_misc` registrations are **kernel-global**, not
per-distro. Verify it yourself in about ten seconds -- register a sentinel in distro A:

```bash
sudo sh -c 'echo ":ZZSentinelProbe:M::\\x7fELF-SENTINEL::/bin/true:" > /proc/sys/fs/binfmt_misc/register'
```

then list `/proc/sys/fs/binfmt_misc/` in distro B. The sentinel is there.

Consequences, both observed:

- **Starting another distro flushes the whole table**, then each distro's `systemd-binfmt`
  re-registers only what its own config declares.
- **`wsl --terminate <other-distro>` removes the `WSLInterop` entry for everyone**, and
  nothing in your distro puts it back.

The symptom is that a Windows command that worked a minute ago now fails with
`exec format error` -- with no visible connection to the other distro you just stopped.

### The self-rescue paradox

Once `WSLInterop` is gone, `wsl.exe` **is itself a Windows binary** and cannot run. You
cannot repair interop through interop. Every recovery path must be local to the distro:

```bash
# Immediate, no interop required:
sudo systemctl restart systemd-binfmt
```

That works because WSL injects a generator drop-in at
`/run/systemd/generator/systemd-binfmt.service.d/override.conf` which re-registers the handler
explicitly. It is present on any systemd-enabled WSL distro, so no `/etc/binfmt.d/` entry of
your own is needed.

For a machine where you routinely start and stop a second distro, automate it with a timer
that re-registers only when the entry is missing, so it never disturbs other handlers:

```ini
# /etc/systemd/system/wsl-binfmt-guard.service
[Unit]
Description=Re-register the WSL interop binfmt handler if it went missing
ConditionPathIsMountPoint=/proc/sys/fs/binfmt_misc

[Service]
Type=oneshot
ExecStart=/bin/sh -c '[ -e /proc/sys/fs/binfmt_misc/WSLInterop ] || echo ":WSLInterop:M::MZ::/init:PF" > /proc/sys/fs/binfmt_misc/register'
```

```ini
# /etc/systemd/system/wsl-binfmt-guard.timer
[Timer]
OnBootSec=20s
OnUnitActiveSec=30s

[Install]
WantedBy=timers.target
```

A related but separate hole: `systemd-binfmt.service` ships
`ExecStop=/usr/lib/systemd/systemd-binfmt --unregister`, which flushes the **shared** table on
graceful shutdown of any one distro. Neutralise it with a drop-in containing an empty
`ExecStop=`. This does **not** help against `wsl --terminate`, which is a hard kill that never
runs `ExecStop` -- only the timer above covers that case.

---

## 5. `--terminate` vs `--shutdown`: Blast Radius

| Command | Effect |
| :--- | :--- |
| `wsl --terminate <distro>` | Stops that one distro. Other distros keep running. |
| `wsl --shutdown` | Stops the **entire** WSL VM -- every distro, including the one you are running in. |

`wsl --shutdown` is required for `/etc/wsl.conf` and `/etc/fstab` changes to take effect. If
you are an agent running inside WSL, **it terminates your own session**: confirm with the user
before running it, and never run it to "just apply a config change" mid-task.

`wsl --terminate <other-distro>` is the safe way to restart a distro you are not living in --
but remember section 4: it will take your `WSLInterop` registration with it.

### `Stopped` is not quiescent if another distro holds a bind mount

With Fedora holding `mount --bind / /mnt/wsl/Ubuntu`, running `wsl --terminate Ubuntu` leaves
that mount **live and writable from Fedora**. `wsl -l -v` reports Ubuntu as `Stopped` the
whole time, `lsblk` still shows its VHDX attached, and a file written during the "stopped"
window is there when Ubuntu next starts -- on the same device, no second attach. Dropping the
last mount is what releases it; after `umount` plus `--terminate`, `lsblk` shows the disk
attached but unmounted.

Two things follow:

- Do not read `Stopped` as "nothing is touching that disk". It is not a quiescence guarantee
  before a copy, a backup, or an image-level operation.
- **VHDX compaction needs `wsl --shutdown`, not `--terminate`** -- see
  [compress-wsl-space](../../compress-wsl-space/SKILL.md). A bind mount held by another distro
  keeps the disk open, and `--terminate` will not clear it.

---

## 6. Checklist Before Touching Another Distro

1. Do you know which distro you are in? `echo "$WSL_DISTRO_NAME"` -- **not** the `*` in
   `wsl -l -v`, which marks the default.
2. Is this a file job? Then bind-mount under `/mnt/wsl` (section 2) instead of reaching for
   `\\wsl.localhost`.
3. Is the target distro's default user able to do what you need, or do you need `-u root`?
4. Did you `cd /mnt/c` first?
5. Did you append `< /dev/null` and pipe through `tr -d '\0\r'`?
6. After the other distro starts or stops, **re-check interop** before assuming a later
   failure is unrelated:
   ```bash
   ls /proc/sys/fs/binfmt_misc/ | grep -q WSLInterop && echo "interop OK" || echo "WSLInterop MISSING"
   ```
