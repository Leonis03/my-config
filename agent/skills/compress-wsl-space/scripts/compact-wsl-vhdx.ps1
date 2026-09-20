[CmdletBinding()]
param(
    [string]$Distro = "Ubuntu",
    [string]$VhdxPath,
    [switch]$Compact,
    [switch]$ForceStopService
)

$ErrorActionPreference = "Stop"

function Format-GiB {
    param([Int64]$Bytes)
    return [Math]::Round($Bytes / 1GB, 2)
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DistroBasePath {
    param([string]$Name)

    $lxss = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    if (-not (Test-Path $lxss)) {
        return $null
    }

    Get-ChildItem $lxss | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath
        if ($props.DistributionName -eq $Name) {
            return $props.BasePath
        }
    }
}

function Get-LinuxUsedBytes {
    param([string]$Name)

    $raw = & wsl -d $Name -- bash -lc "df -B1 --output=used / | tail -n 1 | tr -d ' '" 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return [Int64]$raw.Trim()
}

function Wait-VhdDetached {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $vhd = Get-VHD -Path $Path
        if (-not $vhd.Attached) {
            return $true
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    return $false
}

if (-not $VhdxPath) {
    $basePath = Get-DistroBasePath -Name $Distro
    if ($basePath) {
        $VhdxPath = Join-Path $basePath "ext4.vhdx"
    }
}

if (-not $VhdxPath) {
    $fallbacks = @(
        "D:\WSL\UbuntuFresh\ext4.vhdx",
        "D:\WSL\$Distro\ext4.vhdx"
    )

    foreach ($candidate in $fallbacks) {
        if (Test-Path -LiteralPath $candidate) {
            $VhdxPath = $candidate
            break
        }
    }
}

if (-not $VhdxPath) {
    throw "Could not find VHDX path for distro '$Distro'. Pass -VhdxPath explicitly."
}

if (-not (Test-Path -LiteralPath $VhdxPath)) {
    throw "VHDX path does not exist: $VhdxPath"
}

$initial = Get-Item -LiteralPath $VhdxPath
$linuxUsed = Get-LinuxUsedBytes -Name $Distro

Write-Host "Distro: $Distro"
Write-Host "VHDX: $VhdxPath"
Write-Host "Host VHDX size: $($initial.Length) bytes ($(Format-GiB $initial.Length) GiB)"

if ($linuxUsed) {
    $estimate = [Math]::Max([Int64]0, [Int64]($initial.Length - $linuxUsed))
    Write-Host "Linux used: $linuxUsed bytes ($(Format-GiB $linuxUsed) GiB)"
    Write-Host "Estimated reclaimable: $estimate bytes ($(Format-GiB $estimate) GiB)"
} else {
    Write-Host "Linux used: unavailable from current WSL context"
}

if (-not $Compact) {
    Write-Host "Estimate only. Re-run with -Compact to trim and compact."
    exit 0
}

if (-not (Test-IsAdministrator)) {
    throw "Compaction requires an elevated Administrator PowerShell."
}

if (-not (Get-Command Optimize-VHD -ErrorAction SilentlyContinue)) {
    throw "Optimize-VHD is unavailable. Enable the Hyper-V PowerShell module or use diskpart compact vdisk."
}

Write-Host "Running fstrim..."
& wsl -d $Distro -- bash -lc "df -h / /home; sudo fstrim -av"
if ($LASTEXITCODE -ne 0) {
    throw "fstrim failed for distro '$Distro'."
}

Write-Host "Stopping WSL..."
& wsl --shutdown
Start-Sleep -Seconds 3

if (-not (Wait-VhdDetached -Path $VhdxPath -TimeoutSeconds 30)) {
    if ($ForceStopService) {
        Write-Host "VHDX is still attached. Stopping WSLService..."
        Stop-Service -Name WSLService -Force
        Start-Sleep -Seconds 5
    }
}

$vhd = Get-VHD -Path $VhdxPath
if ($vhd.Attached) {
    throw "VHDX is still attached. Close active WSL sessions or retry with -ForceStopService."
}

Write-Host "Compacting VHDX..."
Optimize-VHD -Path $VhdxPath -Mode Full

$final = Get-Item -LiteralPath $VhdxPath
$reclaimed = $initial.Length - $final.Length

Write-Host "Final VHDX size: $($final.Length) bytes ($(Format-GiB $final.Length) GiB)"
Write-Host "Reclaimed: $reclaimed bytes ($(Format-GiB $reclaimed) GiB)"

Write-Host "Verifying distro startup..."
& wsl -d $Distro -- whoami
& wsl -d $Distro -- bash -lc "df -h / /home"
