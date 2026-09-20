---
name: gpu-cuda-checks
description: Verify that PyTorch CUDA work really runs on the GPU on any rented cloud box, and avoid the silent-CPU-fallback trap. Use when launching or debugging training/inference over SSH -- covers conda activation, a smoke test that proves real GPU compute (is_available() does not), and per-generation gotchas. The Tesla P4 (sm_61, Pascal) is the fully measured case: legacy AMP API on torch 2.2, and why fp16 saves memory but not time without Tensor Cores.
allowed-tools: Bash Read
argument-hint: "[ssh -p PORT user@host]"
arguments: [ssh]
---

# Verifying PyTorch CUDA on a Cloud GPU

General (not project-specific) gotchas for executing PyTorch CUDA code on a rented GPU box.
Pair with `deepln-setup` for installing the environment.

**Sections 1, 2, 5 and 6 are card-agnostic** -- activation, the smoke test, the fallback
trap and long-run hygiene apply to any GPU. **Sections 3 and 4 are generation-specific**;
the Tesla P4 (sm_61 / Pascal) is the one fully measured here.

> Renamed from `p4-cuda`. Use the generic parts as a starting point on a new card, but
> **treat the P4 numbers as P4 numbers** -- section 4 in particular inverts on modern
> hardware, and taking it as a general rule would give you exactly the wrong expectation.

## TL;DR — yes, CUDA runs directly

A correctly-provisioned box runs CUDA out of the box: tensors with `device="cuda"`, autograd, cuDNN, and AMP all work. The only "config" is **activating the right env**. Measured here on a P4 with torch 2.2.1+cu121, numpy<2.

## 1. Activation is the whole game

- **Interactive login** (you type `ssh` and get a `(torch)` prompt): `~/.bashrc` already activated the env — just `python script.py`.
- **Non-interactive `ssh 'cmd'` / scripts / nohup**: conda is NOT auto-activated. `python`/`pip` fall back to system `/usr/bin` (no torch → `ModuleNotFoundError` or CPU-only). Always prefix:

```bash
source /data/miniconda/etc/profile.d/conda.sh && conda activate torch && python script.py
```

(Find the real conda path with `grep -i conda ~/.bashrc`.)

## 2. Verify real GPU compute — run the smoke test

`torch.cuda.is_available()` returning True does **not** mean your work runs on the GPU. Run the bundled script; it handles conda activation itself and exits non-zero if anything critical fails.

```bash
scripts/smoke-test.sh deepln     # over ssh, using the deepln-setup alias
scripts/smoke-test.sh            # on the box itself
scripts/smoke-test.sh --quick    # skip conv / AMP / fp16 checks
scripts/smoke-test.sh --fast     # preflight: versions + device + throughput only
```

| mode | checks | wall time over ssh |
|---|---|---|
| full | everything | ~9 s |
| `--quick` | drops conv, AMP, fp16 | ~7 s |
| `--fast` | versions, device, throughput | ~4 s |

Full mode checks, in order: conda activation and which `python` won, `torch` version pin and `numpy<2`, `cuda.is_available()`, device name, compute capability, free memory, a real 4096² matmul, **the GPU-vs-CPU ratio**, autograd on device, cuDNN conv, the legacy AMP cycle, and fp16-vs-fp32 timing.

`--fast` is meant to be run at the top of a training script or before a long job. It uses a 2048² matmul and an **absolute GFLOP/s floor** rather than a CPU comparison — at that size the CPU side runs only ~100 ms, short enough that scheduler noise and turbo ramp swing the ratio between 2.8x and 7.5x and produce false failures. Throughput is far steadier (measured 1827–2028 GFLOP/s across five runs, against a floor of 500).

**Reference numbers from a healthy P4** (measured 2026-09-15, torch 2.2.1+cu121):

```
torch 2.2.1+cu121 | numpy 1.26.4 | cuda build 12.1
device Tesla P4, sm_61 (6.1), 7.42 GiB total
gpu matmul (4096^2)  10x in ~350 ms   (~3900 GFLOP/s)
gpu matmul (2048^2)  10x in ~90 ms    (~1950 GFLOP/s)
gpu vs cpu speedup   14-15x  (4096^2, full mode)
fp16 vs fp32         0.92-0.94x  (fp16 is SLOWER -- see section 4)
```

**One of these two is the check that catches silent CPU fallback** — `is_available()` will not:

- **full mode:** GPU-vs-CPU ratio at 4096². A healthy P4 lands at 14-15x; under `MIN_SPEEDUP` (default 3) the work is almost certainly on CPU.
- **`--fast`:** absolute throughput floor. A P4 does ~1950 GFLOP/s at 2048²; a CPU matmul is an order of magnitude below `MIN_GFLOPS` (default 500).

Expect `cap (6, 1)`. If you see `(8, x)`/`(9, x)` you're on a different card; if `is_available()` is False, the torch build is wrong (see the fallback trap below). Overrides: `CONDA_SH`, `CONDA_ENV`, `EXPECT_GPU`, `EXPECT_CAP`, `MIN_SPEEDUP`, `MIN_GFLOPS`.

## 3. AMP: use the LEGACY API on torch 2.2

PyTorch 2.2 wants the device-specific AMP API, not the unified `torch.amp.*`:

```python
from torch.cuda.amp import autocast, GradScaler   # correct for torch 2.2
scaler = GradScaler()
with autocast():
    loss = model(x)
scaler.scale(loss).backward(); scaler.step(opt); scaler.update()
```

`torch.amp.autocast("cuda")` exists but the `torch.cuda.amp` form is the safe, documented path for 2.2.

> **This one is about the torch version, not the card.** On modern torch (2.4+) the unified
> `torch.amp.autocast("cuda")` / `torch.amp.GradScaler("cuda")` is the documented form and
> `torch.cuda.amp` is deprecated. Since the old pin is forced by the P4, the legacy API and
> the old card travel together here -- but on a newer card with a current torch, use the
> unified API.

## 4. Generation check — does fp16 actually buy you time?

**This is the section that does NOT generalise.** The answer inverts between generations,
so read the row for the card you are actually on:

| Generation | Tensor Cores | fp16/AMP buys you | Status |
| :--- | :--- | :--- | :--- |
| **Pascal (sm_61)** — P4, P40 | **None** | **Memory only; fp16 is marginally SLOWER** | **Measured: 0.91-0.93x** |
| Turing / Ampere (sm_75-86) — T4, A100 | Yes | Memory **and** significant speedup | Not measured here |
| Ada / Hopper / Blackwell (sm_89+) — L4, H100, RTX 5090 | Yes, plus fp8 on newer | Memory and large speedup; bf16 usually preferred | Not measured here |

The smoke test prints this ratio every run, so it doubles as a card identifier: **a ratio
near 1.0 means no Tensor Cores; anything above ~1.5x means you are not on a Pascal card.**
When you run a new card, record its measured ratio in the table above.

### Pascal detail (measured)

The P4 (GP104, Pascal) has **no Tensor Cores** and runs fp16 at a reduced native rate. AMP still works and lowers memory, but **don't expect a speedup** like on Ampere/Hopper. Pick batch size for memory headroom, not for "fp16 will be 2× faster" — it won't be.

Measured on a real P4 (4096² matmul, torch 2.2.1+cu121): **fp32 ~307 ms vs fp16 ~330 ms — a 0.93x "speedup", i.e. fp16 is slightly *slower*.** The smoke test reports this ratio every run; if you ever see it above ~1.5x you are not on a P4. AMP is still worth enabling when it buys you the memory to raise batch size, but never budget time savings for it here.

A first-step `inf` gradient under `GradScaler` is **normal, not a failure** — the scaler's whole job is to detect the overflow, skip that step, and back the scale off. Judge AMP health by whether grads are finite *after* `scaler.unscale_(opt)` and whether the `step`/`update` cycle advances, not by the raw scaled gradient.

## 5. The silent-CPU-fallback trap

`pip install torch` **without a version pin** installs the newest PyTorch (e.g. 2.12+cu134), which is not built for sm_61. It can import, report `cuda.is_available()` oddly, or fall back to CPU and run training ~50× slower with no error. **Never** run unpinned `pip install torch` on a P4 — always pin `torch==2.2.1+cu121` (see `deepln-setup`). If training is mysteriously slow, run `scripts/smoke-test.sh` first -- the GPU-vs-CPU ratio it reports is the fastest way to confirm or rule this out.

## 6. Long runs

```bash
nohup python -u train.py > /tmp/training.log 2>&1 &
tail -f /tmp/training.log
```

Use `-u` for unbuffered output, and `nvidia-smi -l 2` (or `watch -n2 nvidia-smi`) to confirm GPU utilization is non-zero — a busy P4 sitting near 0% util usually means the CPU-fallback trap.
