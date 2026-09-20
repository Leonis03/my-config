# `/etc` Diff Analysis

Date: 2026-03-30

Compared:

- old `/etc`: [`ubuntu-etc-20260330-230418.tar`](/C:/Users/<your-windows-user>/move/ubuntu-etc-20260330-230418.tar)
- fresh baseline `/etc`: [`ubuntuFresh-etc-before-restore-20260330-233510.tar`](/C:/Users/<your-windows-user>/move/ubuntuFresh-etc-before-restore-20260330-233510.tar)

Baseline is a freshly installed `UbuntuFresh` on WSL Ubuntu 24.04 before the old `/etc` restore.

## High-confidence user changes

### 1. WSL behavior customization

`/etc/wsl.conf` in the old system added:

```ini
[user]
default=<your-linux-user>

[interop]
enabled=true
appendWindowsPath=false
```

The fresh baseline only had:

```ini
[boot]
systemd=true
```

Interpretation: this is a clear intentional WSL customization.

### 2. Passwordless sudo

`/etc/sudoers` in the old system had:

```text
<your-linux-user> ALL=(ALL) NOPASSWD: ALL
```

Interpretation: explicit user customization.

### 3. Preserve proxy env under sudo

Old system had an extra file:

`/etc/sudoers.d/proxy-env`

with:

```text
Defaults env_keep += "HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy"
```

Interpretation: explicit user customization to keep proxy variables when using `sudo`.

### 4. APT mirror changed

`/etc/apt/sources.list.d/ubuntu.sources` was changed from the stock Ubuntu archive/security endpoints to:

```text
https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
```

The old system also kept a backup file:

`/etc/apt/sources.list.d/ubuntu.sources.bak`

Interpretation: explicit user customization of package sources.

## Likely user-created account state

The old system's `<your-linux-user>` account had more supplemental groups than the fresh baseline:

- `adm`
- `cdrom`
- `dip`
- `plugdev`
- `users`
- `sudo`

Interpretation: this may come from the way the user was originally created or later `usermod` changes. It is user/account state, but not necessarily a later manual edit to `/etc/group`.

## Likely package-install side effects, not hand-edited config

These top-level entries existed only in the old system:

- `/etc/.java`
- `/etc/apache2`
- `/etc/java-21-openjdk`
- `/etc/lighttpd`
- `/etc/openal`
- `/etc/pulse`
- `/etc/vdpau_wrapper.cfg`

Interpretation: these strongly suggest packages had been installed in the old distro, especially Java and web/media-related packages. This is better understood as "software footprint" than "hand-edited config".

Other package-derived extras seen only in the old system:

- `/etc/default/cacerts`
- `/etc/ca-certificates/update.d/jks-keystore`
- `/etc/cloud/cloud-init.disabled`
- `/etc/dpkg/shlibs.default`
- `/etc/dpkg/shlibs.override`
- `/etc/ld.so.conf.d/fakeroot-x86_64-linux-gnu.conf`

## Low-signal / generated differences

These changed, but are not good evidence of intentional user config edits:

- `/etc/machine-id`
- `/etc/passwd`, `/etc/shadow`, `/etc/group`, `/etc/gshadow`
- `/etc/landscape/client.conf` (`computer_title` differed because distro name differed)
- `/etc/ld.so.cache`

## Negative findings

No meaningful differences were found in:

- `/etc/profile.d`
- `/etc/ssh`

So there is no obvious sign of extra user-authored drop-in shell or SSH config under those paths.

## Bottom line

The most important user-originated `/etc` changes in the old distro were:

1. customized WSL behavior in `/etc/wsl.conf`
2. passwordless sudo for `<your-linux-user>`
3. preserving proxy env via `/etc/sudoers.d/proxy-env`
4. switching APT to the Tsinghua mirror

Everything else high-signal is mostly package footprint rather than direct user-edited config.
