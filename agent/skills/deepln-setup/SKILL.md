---
name: deepln-setup
description: Connect to and provision a rented DeepLN cloud GPU node over SSH -- any card, not just the Tesla P4. Use when setting up or repairing a PyTorch CUDA environment on a rented box, when a new rental needs the `deepln` SSH alias repointed, when torch/torchvision/numpy are missing or mismatched for the card (silent CPU fallback), or when installing via SJTU/Tsinghua mirrors. Handles the rental lifecycle, conda detection, non-interactive activation, cgroup capacity limits, and fast mirror selection. Carries verified version pins for the Tesla P4 (sm_61, Pascal).
allowed-tools: Bash Read
argument-hint: "[ssh -p PORT user@host | ssh deepln]"
arguments: [ssh]
---

# DeepLN Cloud GPU: Connection & Environment Setup

Provision or repair a PyTorch CUDA environment on a rented **DeepLN** node.

Everything in sections 0-2 and 4-5 is **card-agnostic** -- the SSH alias and rental
lifecycle, the conda-activation trap, cgroup capacity, mirror selection, verification.
Only the **version pins** depend on which GPU you drew; see the table below.

> Renamed from `p4-setup`. The old name made agents skip this skill on non-P4 rentals,
> which meant rediscovering the conda trap from scratch every time. The P4-specific
> parts were always a small minority of the file.

## Version pins by GPU generation

**Check what you actually got before installing anything:**

```bash
ssh deepln 'nvidia-smi --query-gpu=name,compute_cap,memory.total,driver_version --format=csv,noheader'
```

| Compute cap | Generation | Card examples | PyTorch | Status |
| :--- | :--- | :--- | :--- | :--- |
| **sm_61** | Pascal | **Tesla P4**, P40, GTX 10xx | **≤ 2.2.x + cu121/cu118, numpy < 2** | **Verified** (see below) |
| sm_75 / sm_80 / sm_86 | Turing / Ampere | T4, A100, A10, RTX 30xx | Modern torch, no special pin | Not tested here |
| sm_89 | Ada | L4, L40S, RTX 40xx | Modern torch | Not tested here |
| sm_90 / sm_120 | Hopper / Blackwell | H100, **RTX 5090** | **Needs a recent torch + CUDA 12.8+**; old builds will not run | Not tested here |

**Only the sm_61 row is measured on this fleet.** The others are the general PyTorch
support matrix, recorded so you know which way to look -- confirm against the official
install matrix before trusting them, and add a verified row here once you have run a card.

**The rule that generalises**: the pin must bracket the card from *both* sides. Old cards
break on torch that is too new (no sm_61 kernels -> silent CPU fallback); new cards break on
torch that is too old (no sm_120 kernels -> the same silent fallback). `cuda.is_available()`
returning True does not settle it either way -- run the smoke test in `gpu-cuda-checks`.

### The Tesla P4 pin (verified)

The P4 is old hardware: it only works with **PyTorch <= 2.2.x built for cu121 (or cu118)**
and **numpy < 2**. Newer PyTorch (2.3+) either fails to build for sm_61 or silently falls
back to CPU.

## 0. Connect & SSH Config Alias (`deepln`)

### SSH Config Alias
Local `~/.ssh/config` defines the `deepln` alias for direct, key-authenticated connection without retyping port and host:

```ssh-config
Host deepln
    HostName <instance-domain>.deepln.com
    Port <ssh-port>
    User root
    IdentityFile ~/.ssh/id_ed25519
    KexAlgorithms curve25519-sha256,diffie-hellman-group-exchange-sha256,ecdh-sha2-nistp256
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

- **Direct Alias Usage**: You can connect directly via `ssh deepln` once configured.
- **Instance Rental Lifecycle**: DeepLN creates dynamic domain names and ports on each rental. Whenever a new instance is launched (e.g. `ssh -p <ssh-port> root@<instance>.deepln.com`), update `HostName` and `Port` under `Host deepln` in `~/.ssh/config` after verifying the environment. Subsequent commands and automation should use `ssh deepln`.
- **Never add a `*.deepln.com` wildcard to that `Host` line.** A wildcard makes the stanza match every deepln hostname you type while `HostName` still forces the one hardcoded below it, so `ssh -p NEW root@new-instance.deepln.com` silently connects to the *old* box. Symptoms look like a dead rental or a wiped environment. Keep the stanza to the bare alias.

**Use the bundled script instead of hand-editing** — it parses the rental string, verifies the box is reachable and really is a P4 with a working torch env, backs up `~/.ssh/config`, and rewrites only `HostName`/`Port`/`User` inside the `Host deepln` stanza (other hosts untouched). It refuses to write if verification fails, so the alias never points at a dead or wrong machine.

```bash
scripts/set-deepln.sh 'ssh -p <ssh-port> root@abc123.deepln.com'   # paste the rental string verbatim
scripts/set-deepln.sh --show                                  # current target + live status + GPU
scripts/set-deepln.sh --help                                  # other input forms and flags
```

### Connection & Retry Loop

```!
echo "SSH argument: $ssh"
```

If no SSH argument is given, check whether `ssh deepln` connects. Otherwise, ask for `ssh -p PORT user@host` (or `ssh deepln`). The box's DNS can be flaky from some networks — wrap connections in a retry loop:

```bash
# Using alias:
for i in $(seq 1 8); do ssh deepln 'echo OK' && break; echo "retry $i"; sleep 4; done

# Using explicit host/port:
for i in $(seq 1 8); do ssh -p PORT user@host 'echo OK' && break; echo "retry $i"; sleep 4; done
```

### Node capacity: `nproc` and `MemTotal` are NOT what you get

These boxes are containers. `nproc`, `/proc/cpuinfo` and `/proc/meminfo` report the
**host's** hardware; what you may actually consume is the **cgroup quota**. Read the
quota before sizing any worker pool, `-j` flag or batch:

```bash
ssh deepln 'awk "{printf \"CPU: %.2f cores\n\", \$1/\$2}" /sys/fs/cgroup/cpu.max
            awk "{printf \"MEM: %.1f GiB\n\", \$1/1073741824}" /sys/fs/cgroup/memory.max'
```

Measured on the deepln P4 node (2026-09-20; the CPU figure matches a 2026-05 reading,
so it is stable across rentals):

| | `nproc` / `MemTotal` says | cgroup quota | overstated by |
| :--- | :--- | :--- | ---: |
| CPU | 64 | **8.83 cores** (`cpu.max 883300 100000`) | 7.2x |
| RAM | 125.8 GB | **18 GiB** (`memory.max 19327352832`) | 7.0x |

Rest of the node: Xeon E5-2683 v4 @ 2.10GHz, Tesla P4 8192 MiB (sm_61, driver 550.54.15),
`/data` 50G, `/` 30G.

- **Start at `-j 8`, never `-j 48`.** Oversubscribing the CPU quota is how a 3 s batch
  became 680 s (see `tools/remote-ssh.md` section 3).
- **The RAM lie is the dangerous one.** Sizing a job against 125 GB gets it OOM-killed at
  18 GiB, usually leaving nothing but exit code 137. Check with `dmesg | grep -i oom`.
- **Re-measure on every new rental.** A sibling node in the same fleet reported `nproc`
  256 while granting only 24 cores.

> `/data` is the only path preserved across rentals -- put datasets and checkpoints there,
> not in `/root`.

## 1. Find conda and activate the env (CRITICAL)

**A non-interactive `ssh 'command'` does NOT source conda.** `pip`/`python` then resolve to the *system* `/usr/bin` (no torch), so anything you install lands in the wrong interpreter. The interactive prompt shows `(envname)` only because `~/.bashrc` activates it.

Discover the real conda path and env, then always activate explicitly:

```bash
ssh ... 'grep -iE "conda|activate" ~/.bashrc | head'   # reveals conda.sh path + env name
```

Common location is `/data/miniconda` (deepln images) or `/opt/conda`, `~/miniconda3`. Activate before every command:

```bash
source /data/miniconda/etc/profile.d/conda.sh && conda activate torch
which pip python && python --version
```

If there is **no conda at all**, just use system `python3`/`pip` — but then the whole machine is your "env"; the version rules below still apply.

## 2. Check what's already installed

Many cloud images (e.g. `ubuntu2204-py310-cu121-pytorch2.2.1`) ship the correct versions pre-installed — **check before downloading anything**:

```bash
python -c "import torch,torchvision,numpy as np; print('torch',torch.__version__,'tv',torchvision.__version__,'numpy',np.__version__,'cuda',torch.cuda.is_available(),torch.version.cuda)"
```

Decision table:

| Result | Action |
|---|---|
| `2.2.1+cu121`, `0.17.1+cu121`, numpy `1.26.x`, cuda `True` | **Done — install nothing.** Go verify (step 4). |
| torch missing / ModuleNotFound | Install (step 3). |
| torch ≥ 2.3 or no `+cuXXX` tag, or `cuda False` | Wrong/too-new — reinstall pinned (step 3). |
| numpy ≥ 2 | `pip install "numpy<2" -i https://pypi.tuna.tsinghua.edu.cn/simple` |

## 3. Install the pinned old versions

**numpy first** (Tsinghua PyPI, ~50 MB/s):

```bash
pip install "numpy<2" -i https://pypi.tuna.tsinghua.edu.cn/simple
```

**torch + torchvision** — use SJTU find-links AND pin the explicit `+cu121` local version:

```bash
pip install torch==2.2.1+cu121 torchvision==0.17.1+cu121 -f https://mirror.sjtu.edu.cn/pytorch-wheels/cu121/
```

> ⚠️ The `+cu121` suffix is mandatory. With a bare `torch==2.2.1`, pip considers the PyPI `manylinux1` wheel an equal match and often downloads *that* from pypi.org at **~130 KB/s** (and it stalls), pulling extra `nvidia-*-cu12` deps. Pinning `+cu121` forces the self-contained SJTU wheel at full speed. Use `-f` (find-links), **not** `--index-url`.

### Mirror speed reference (tested 2026-05, deepln cloud)

| Mirror | URL | Speed | Note |
|---|---|---|---|
| **上海交大** | `mirror.sjtu.edu.cn/pytorch-wheels/cu121/` | **~35 MB/s** | 首选；301 跳转到 jcloud S3，正常 |
| 官方 | `download.pytorch.org/whl/cu121` | ~2 MB/s | `--index-url` 备用 |
| 阿里云 | `mirrors.aliyun.com/pytorch-wheels/cu121/` | ~0.4 MB/s | 不推荐 |
| 清华 | `pypi.tuna.tsinghua.edu.cn` | — | **只有 CPU 版 torch**，非 PyPI 包用它，CUDA torch 不能用 |

Fallback if SJTU is down: `pip install torch==2.2.1 torchvision==0.17.1 --index-url https://download.pytorch.org/whl/cu121`

## 4. Verify with REAL GPU compute

`cuda.is_available()` alone is not enough — run an actual kernel:

```bash
python - <<'EOF'
import torch
print("torch", torch.__version__, "| cuda build", torch.version.cuda)
print("device:", torch.cuda.get_device_name(0), "| cap", torch.cuda.get_device_capability(0))
x = torch.randn(2048,2048,device="cuda",requires_grad=True)
y = (x @ torch.randn(2048,2048,device="cuda")).relu().sum()
y.backward()
with torch.cuda.amp.autocast():
    _ = (x @ x).float().mean()
print("matmul+backward+amp OK, grad on cuda:", x.grad.is_cuda)
EOF
```

Expect `cap (6, 1)` for the P4 and `OK`. See the `gpu-cuda-checks` skill for runtime gotchas (AMP API, no Tensor Cores).
