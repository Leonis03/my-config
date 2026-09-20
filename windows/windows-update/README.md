# 锁住 Windows 功能更新，但保留更新可见性

把 Windows 11 钉在 24H2，不让它推 25H2；同时**仍然能在设置里看到**质量更新、Defender 定义、可选更新，并保留驱动更新。

目录里两个 `.reg`，都是纯 ASCII、LF 行尾，导入后重启（或 `gpupdate /force`）生效。

| 文件 | 做什么 | 什么时候用 |
| :--- | :--- | :--- |
| [`wu-stay-24h2-notify.reg`](wu-stay-24h2-notify.reg) | 钉版本 + 下载/安装前通知 | **常用的一份。** 明确不想要下一个功能更新 |
| [`wu-notify-minimal.reg`](wu-notify-minimal.reg) | 只改通知策略，不钉版本 | 只想要「更新前先问我」，功能更新照常推 |

## 两组键各管什么

```
HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
    ProductVersion            = "Windows 11"     产品线
    TargetReleaseVersion      = 1                启用版本钉选
    TargetReleaseVersionInfo  = "24H2"           钉在哪个版本
    DisableWindowsUpdateAccess        = 删除     ← 确保设置页不被锁死
    DoNotConnectToWindowsUpdateInternetLocations = 删除

HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU
    AUOptions    = 2    下载前通知、安装前通知
    NoAutoUpdate = 0    不禁用自动更新（否则整块更新会静默停摆）
```

**那两行 `=-`（删除值）是这套配置的关键，也是它和网上常见做法的区别。** 大多数「关闭 Windows 更新」的教程会顺手设上 `DisableWindowsUpdateAccess=1`，结果是设置页里整块更新界面被禁用——你锁住了版本，同时也失去了「看到有哪些安全更新可装」的能力。这里显式把它们删掉，换来的是**版本不动、但更新依然可见可选装**。

`NoAutoUpdate=0` 同理：它不是笔误。设成 `1` 会让 `AUOptions` 失去意义，整个自动更新链路停掉。

## 验证

```powershell
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /reg:64
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /reg:64
```

本机实测（2026-09-21，Windows 10.0.26100.7627）：

```
ProductVersion            REG_SZ       Windows 11
TargetReleaseVersion      REG_DWORD    0x1
TargetReleaseVersionInfo  REG_SZ       24H2
AUOptions                 REG_DWORD    0x2
NoAutoUpdate              REG_DWORD    0x0
```

从 WSL 里查要加 `/reg:64`，否则 32 位重定向会让键「明明存在却找不到」——见
[`../../agent/skills/wsl-windows-command/`](../../agent/skills/wsl-windows-command/)。

## 这套策略对 WSL 完全无效

**钉住 Windows 不等于钉住 WSL。** WSL 与 WSL2 内核走 Microsoft Store / `wsl --update`，是**另一条完全独立的渠道**，上面这些 `Policies\...\WindowsUpdate` 键对它没有任何约束力。

后果是双向的：既没拦住 WSL 自己更新，也没让你因为「我锁了更新」而免于 WSL 的安全修复——你只是不知道它变了。

实测见 [`../../wsl/setup/README.md`](../../wsl/setup/README.md) 的维护节：WSL 从 2.7.8.0 跳到 2.7.14.0、内核从 6.18.33.1 到 6.18.33.2-2 的同时，**Windows 版本号 26100.7627 一动没动**。
