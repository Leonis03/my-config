# WSL Ubuntu 迁移到 D 盘

## 结论

当前机器优先使用：

```powershell
wsl --manage Ubuntu --move D:\WSL\Ubuntu
```

只有当本机 `wsl --help` 里没有 `--manage <Distro>` / `--move <Location>` 时，才使用“导出 -> 注销 -> 导入”的兼容方案。

## 当前情况

- 发行版名：`Ubuntu`
- 当前 WSL 版本：`2.6.3.0`
- 当前根盘文件：`C:\Users\<your-windows-user>\AppData\Local\wsl\{<distro-guid>}\ext4.vhdx`
- 当前目录占用：约 `19G`
- 当前默认用户：`<your-linux-user>`（系统内 `/etc/wsl.conf` 已配置）

## 目标

把 Ubuntu 的 WSL2 根盘从 `C:` 挪到 `D:`。

- 推荐目标目录：`D:\WSL\Ubuntu`
- 备份目录：`D:\WSL\backup`

说明：

- 对 `wsl --manage ... --move ...` 来说，目标是目录，不是具体的 `ext4.vhdx` 文件。
- 如果使用兼容方案，最终会得到 `D:\WSL\Ubuntu\ext4.vhdx` 这样的文件路径。

## 迁移前检查

以下命令在 Windows PowerShell 中执行，不是在 WSL 终端里执行。

```powershell
wsl --version
wsl --help
wsl -l -v
```

满足以下条件再继续：

- `wsl --help` 里能看到 `--manage <Distro>` 和 `--move <Location>`
- `wsl -l -v` 里能看到目标发行版名确实是 `Ubuntu`
- `D:` 至少预留 `25G+` 空间
- 关闭所有正在使用 WSL 的终端、IDE、Docker Desktop、后台服务

## 推荐方案：先备份，再直接 move

以下命令在 Windows PowerShell 中执行。

```powershell
$stamp = Get-Date -Format yyyyMMdd-HHmmss
$backup = "D:\WSL\backup\Ubuntu-pre-move-$stamp.vhdx"

New-Item -ItemType Directory -Force D:\WSL\backup | Out-Null
New-Item -ItemType Directory -Force D:\WSL\Ubuntu | Out-Null

# 先导出一份可回滚的备份
wsl --shutdown
wsl --export Ubuntu $backup --format vhd
Get-Item $backup

# 直接把现有发行版迁移到 D 盘
wsl --manage Ubuntu --move D:\WSL\Ubuntu
```

## 迁移后校验

### 基础校验

```powershell
wsl -l -v
wsl -d Ubuntu -- whoami
wsl -d Ubuntu -- sh -lc "df -h / && findmnt /"
Get-Item D:\WSL\Ubuntu\ext4.vhdx | Select-Object FullName,Length,LastWriteTime
```

预期结果：

- `wsl -l -v` 里仍能看到 `Ubuntu`，版本为 `2`
- `whoami` 返回 `<your-linux-user>`
- `/` 挂载正常，容量显示正常
- `D:\WSL\Ubuntu\ext4.vhdx` 存在

### 强校验

如果你想进一步证明“当前根盘确实正在写入 `D:\WSL\Ubuntu\ext4.vhdx`”，可以做一次探针写入：

```powershell
$before = (Get-Item D:\WSL\Ubuntu\ext4.vhdx).LastWriteTime
wsl -d Ubuntu -- sh -lc "dd if=/dev/zero of=~/wsl-move-probe.bin bs=1M count=16 status=none && sync"
$after = (Get-Item D:\WSL\Ubuntu\ext4.vhdx).LastWriteTime
"$before -> $after"
wsl -d Ubuntu -- rm ~/wsl-move-probe.bin
```

预期结果：

- `D:\WSL\Ubuntu\ext4.vhdx` 的 `LastWriteTime` 更新
- 说明刚才在 Linux 根文件系统里的写入，已经落到了 `D:` 盘这块 VHDX 上

## 如果默认用户不对

当前版本优先使用：

```powershell
wsl --manage Ubuntu --set-default-user <your-linux-user>
wsl --shutdown
wsl -d Ubuntu -- whoami
```

如果本机不支持 `--set-default-user`，再回到 `/etc/wsl.conf` 方案，确认其中包含：

```ini
[user]
default=<your-linux-user>
```

保存后执行：

```powershell
wsl --shutdown
wsl -d Ubuntu -- whoami
```

## 兼容旧版 WSL 的回退方案

只有在本机没有 `wsl --manage ... --move ...` 时，再使用下面这套。

```powershell
wsl --shutdown
New-Item -ItemType Directory -Force D:\WSL\Ubuntu | Out-Null

# 导出当前 Ubuntu 为 VHDX
wsl --export Ubuntu D:\WSL\Ubuntu\ext4.vhdx --format vhd
Get-Item D:\WSL\Ubuntu\ext4.vhdx

# 只有在已经保留了额外备份，且确认要走兼容方案时，再继续
wsl --unregister Ubuntu
wsl --import-in-place Ubuntu D:\WSL\Ubuntu\ext4.vhdx
```

完成后，重复执行上面的“迁移后校验”。

## 注意事项

- `wsl --manage Ubuntu --move D:\WSL\Ubuntu` 的目标是目录，不是文件路径。
- 推荐先做一次导出备份，再做 `--move`。这样即使迁移失败，也有单独的回滚文件。
- 兼容方案里的 `wsl --unregister Ubuntu` 是破坏性操作，只能在确认备份可用后执行。
- `/mnt/c`、`/mnt/d` 这类挂载的 Windows 文件不会跟着一起“搬迁”。
- 建议把 WSL 放在本机固定磁盘上，不建议放到容易断开的外置盘。
- 如果迁移后旧路径还残留文件，不要立刻手动删，先确认新路径稳定使用几天。

## 以后新装时避免再落到 C 盘

如果以后新安装发行版，可以直接指定位置：

```powershell
wsl --install Ubuntu --location D:\WSL\Ubuntu
```

这只影响新安装，不会迁移已经存在的发行版。

## 参考

- Microsoft Learn: https://learn.microsoft.com/en-us/windows/wsl/basic-commands
- Microsoft Learn: https://learn.microsoft.com/en-us/windows/wsl/wsl-config
- Microsoft Learn: https://learn.microsoft.com/en-us/windows/wsl/disk-space
