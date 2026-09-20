#!/usr/bin/env bash
# smoke-test.sh -- prove a Tesla P4 box can actually run PyTorch CUDA work.
#
# Goes past `torch.cuda.is_available()`, which returns True on setups that then
# silently run on CPU. The decisive check is measured throughput: full mode uses
# the GPU-vs-CPU matmul ratio at 4096^2 (healthy P4: 14-15x), --fast uses an
# absolute GFLOP/s floor at 2048^2 (healthy P4: ~1950, floor 500). A CPU fallback
# misses either by a wide margin.
#
# Usage:
#   smoke-test.sh                 # run on the P4 box itself
#   smoke-test.sh deepln          # run over ssh against the deepln-setup alias
#   smoke-test.sh -p <ssh-port> root@host.deepln.com
#   smoke-test.sh --quick         # skip the slower fp16/conv/AMP checks
#   smoke-test.sh --fast          # ~4s preflight: versions + device + throughput only
#
# Env overrides: CONDA_SH, CONDA_ENV, EXPECT_GPU, EXPECT_CAP, MIN_SPEEDUP, MIN_GFLOPS
# Exit codes: 0 all critical checks passed | 1 a critical check failed | 2 usage/ssh error

set -uo pipefail

QUICK="${QUICK:-0}"     # may arrive from the env when re-run over ssh
FAST="${FAST:-0}"
SSH_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --quick)   QUICK=1; shift ;;
        --fast)    FAST=1; QUICK=1; shift ;;
        -h|--help) sed -n "2,19p" "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)         SSH_ARGS+=("$1"); shift ;;
    esac
done

# ---------- remote dispatch: re-run this same script on the box ----------
if [ "${#SSH_ARGS[@]}" -gt 0 ] && [ -z "${P4_SMOKE_REMOTE:-}" ]; then
    echo "running smoke test on: ${SSH_ARGS[*]}"
    echo
    ssh -o BatchMode=yes -o ConnectTimeout=20 "${SSH_ARGS[@]}" \
        "P4_SMOKE_REMOTE=1 QUICK=$QUICK FAST=$FAST bash -s" < "$0"
    rc=$?
    [ $rc -eq 255 ] && { echo "error: ssh failed to connect" >&2; exit 2; }
    exit $rc
fi

CONDA_ENV="${CONDA_ENV:-torch}"
EXPECT_GPU="${EXPECT_GPU:-Tesla P4}"
EXPECT_CAP="${EXPECT_CAP:-6.1}"
MIN_SPEEDUP="${MIN_SPEEDUP:-3.0}"

# ---------- activate conda (non-interactive ssh does NOT do this for you) ----------
echo "== environment =="
if [ -z "${CONDA_SH:-}" ]; then
    for c in /data/miniconda /opt/conda "$HOME/miniconda3" "$HOME/anaconda3" /usr/local/conda; do
        [ -f "$c/etc/profile.d/conda.sh" ] && { CONDA_SH="$c/etc/profile.d/conda.sh"; break; }
    done
fi
if [ -n "${CONDA_SH:-}" ] && [ -f "$CONDA_SH" ]; then
    # shellcheck disable=SC1090
    source "$CONDA_SH" && conda activate "$CONDA_ENV" 2>/dev/null
    echo "  conda   $CONDA_SH  (env: ${CONDA_DEFAULT_ENV:-none})"
else
    echo "  conda   not found -- falling back to system python"
fi
PY=$(command -v python || command -v python3)
[ -n "$PY" ] || { echo "error: no python on PATH" >&2; exit 2; }
echo "  python  $PY"
case "$PY" in
    /usr/bin/*) echo "  WARN: using system python -- conda env was not activated" ;;
esac
echo "  host    $(hostname)"
echo

QUICK="$QUICK" FAST="$FAST" EXPECT_GPU="$EXPECT_GPU" EXPECT_CAP="$EXPECT_CAP" MIN_SPEEDUP="$MIN_SPEEDUP" MIN_GFLOPS="${MIN_GFLOPS:-500}" \
"$PY" - <<'PYEOF'
import os, sys, time

QUICK       = os.environ.get("QUICK", "0") == "1"
FAST        = os.environ.get("FAST",  "0") == "1"   # preflight: small matrix, core checks only
EXPECT_GPU  = os.environ.get("EXPECT_GPU", "Tesla P4")
EXPECT_CAP  = os.environ.get("EXPECT_CAP", "6.1")
MIN_SPEEDUP = float(os.environ.get("MIN_SPEEDUP", "3.0"))
MIN_GFLOPS  = float(os.environ.get("MIN_GFLOPS", "500"))   # fast mode: absolute floor,
                                                           # a CPU matmul lands far below this

fails, warns = [], []
def row(status, name, detail=""):
    color = {"PASS": "\033[32m", "FAIL": "\033[31m", "WARN": "\033[33m", "INFO": "\033[36m"}[status]
    print(f"  {color}{status:<4}\033[0m {name:<26} {detail}")
def ok(n, d=""):   row("PASS", n, d)
def bad(n, d=""):  row("FAIL", n, d); fails.append(n)
def warn(n, d=""): row("WARN", n, d); warns.append(n)
def info(n, d=""): row("INFO", n, d)

print("== versions ==")
try:
    import torch
except Exception as e:
    print(f"  \033[31mFAIL\033[0m torch import          {e}")
    print("\nCRITICAL: torch is not importable in this env. See the deepln-setup skill.")
    sys.exit(1)

tv = torch.__version__
ok("torch import", tv)
# The P4 needs a cu12x build of torch 2.2.x; anything newer is the silent-fallback trap.
if tv.startswith("2.2") and "+cu12" in tv:
    ok("torch version pin", tv)
elif "+cu" not in tv:
    bad("torch version pin", f"{tv} -- no +cuXXX tag, likely a CPU-only wheel")
else:
    warn("torch version pin", f"{tv} -- expected 2.2.x+cu121 for sm_61")

try:
    import numpy as np
    (ok if int(np.__version__.split(".")[0]) < 2 else bad)(
        "numpy < 2", np.__version__)
except Exception as e:
    warn("numpy", str(e))

print("\n== device ==")
if not torch.cuda.is_available():
    bad("cuda.is_available", "False -- wrong torch build or no driver")
    print("\nCRITICAL: no CUDA device. Nothing further can be tested.")
    sys.exit(1)
ok("cuda.is_available", "True")
info("cuda build", str(torch.version.cuda))

name = torch.cuda.get_device_name(0)
(ok if EXPECT_GPU in name else warn)("device name", f"{name} (expected {EXPECT_GPU})")

cap = torch.cuda.get_device_capability(0)
caps = f"{cap[0]}.{cap[1]}"
if caps == EXPECT_CAP:
    ok("compute capability", f"sm_{cap[0]}{cap[1]} ({caps})")
else:
    warn("compute capability", f"{caps} -- expected {EXPECT_CAP}; this is not a P4")

free, total = torch.cuda.mem_get_info()
info("memory", f"{free/2**30:.2f} GiB free / {total/2**30:.2f} GiB total")

print("\n== real compute ==")
N = 2048 if FAST else 4096
try:
    x = torch.randn(N, N, device="cuda")
    torch.cuda.synchronize()
    for _ in range(3):                      # warm up kernels + autotune
        _ = x @ x
    torch.cuda.synchronize()
    t = time.time()
    for _ in range(10):
        y = x @ x
        y = y / y.norm()
    torch.cuda.synchronize()
    gpu_ms = (time.time() - t) * 1000
    if not torch.isfinite(y).all():
        bad("matmul finite", "result contains inf/nan")
    else:
        gflops = 10 * 2 * N**3 / (gpu_ms / 1000) / 1e9
        ok("gpu matmul", f"10x {N}^2 in {gpu_ms:.0f} ms  (~{gflops:.0f} GFLOP/s)")
except Exception as e:
    bad("gpu matmul", str(e)); gpu_ms = None

# The decisive fallback check. Two ways to make it, picked by mode:
#   fast  -- absolute GFLOP/s floor. No CPU run, and stable: at 2048^2 the CPU
#            side is only ~100 ms, short enough that scheduler noise and turbo
#            ramp swing a relative ratio by 2-3x and cause false failures.
#   full  -- GPU-vs-CPU ratio at 4096^2, where both sides run long enough to be
#            stable (measured 14-15x on a healthy P4) and the signal is stronger.
if gpu_ms is not None:
    if FAST:
        if gflops >= MIN_GFLOPS:
            ok("gpu throughput", f"{gflops:.0f} GFLOP/s (floor {MIN_GFLOPS:.0f}) -- far above CPU range")
        else:
            bad("gpu throughput",
                f"only {gflops:.0f} GFLOP/s (need >={MIN_GFLOPS:.0f}) -- work is probably running on CPU")
    else:
        xc = torch.randn(N, N)
        t = time.time()
        for _ in range(2):
            yc = xc @ xc
            yc = yc / yc.norm()
        cpu_ms = (time.time() - t) * 1000 * 5      # scale 2 iters -> 10
        speedup = cpu_ms / gpu_ms
        if speedup >= MIN_SPEEDUP:
            ok("gpu vs cpu speedup", f"{speedup:.1f}x  (cpu ~{cpu_ms:.0f} ms)")
        else:
            bad("gpu vs cpu speedup",
                f"only {speedup:.1f}x (need >={MIN_SPEEDUP}) -- work is probably running on CPU")

if not FAST:
    print("\n== autograd / cudnn ==")
    try:
        a = torch.randn(1024, 1024, device="cuda", requires_grad=True)
        (a @ torch.randn(1024, 1024, device="cuda")).relu().sum().backward()
        if a.grad is not None and a.grad.is_cuda and torch.isfinite(a.grad).all():
            ok("autograd on cuda", "grad finite and on device")
        else:
            bad("autograd on cuda", "grad missing, on cpu, or non-finite")
    except Exception as e:
        bad("autograd on cuda", str(e))

if not QUICK:
    try:
        import torch.nn as nn
        conv = nn.Conv2d(3, 16, 3, padding=1).cuda()
        out = conv(torch.randn(8, 3, 64, 64, device="cuda"))
        (ok if torch.isfinite(out).all() else bad)("cudnn conv2d", f"out {tuple(out.shape)}")
    except Exception as e:
        bad("cudnn conv2d", str(e))

    print("\n== amp (legacy api, required on torch 2.2) ==")
    try:
        import torch.nn as nn
        from torch.cuda.amp import autocast, GradScaler
        model = nn.Linear(512, 512).cuda()
        opt = torch.optim.SGD(model.parameters(), lr=1e-3)
        scaler = GradScaler()
        xb = torch.randn(64, 512, device="cuda")

        with autocast():
            out = model(xb)
            cast_dtype = out.dtype          # proves autocast actually engaged
            loss = out.pow(2).mean()
        (ok if cast_dtype == torch.float16 else warn)(
            "autocast dtype", f"forward ran in {cast_dtype}")

        # Full scaler cycle. A first-step inf is normal -- GradScaler skips the
        # step and backs the scale off; what matters is that unscaled grads are
        # finite and the state machine advances.
        s0 = scaler.get_scale()
        scaler.scale(loss).backward()
        scaler.unscale_(opt)
        g = model.weight.grad
        if g is None or not torch.isfinite(g).all():
            bad("amp grads", "grad missing or non-finite after unscale_")
        else:
            ok("amp grads", f"finite after unscale_ (|g|={g.norm():.3g})")
        scaler.step(opt)
        scaler.update()
        ok("GradScaler cycle", f"scale {s0:.0f} -> {scaler.get_scale():.0f}")
    except Exception as e:
        bad("torch.cuda.amp", str(e))

    # Pascal has no Tensor Cores: fp16 should save memory but NOT gain speed.
    try:
        def bench(dtype):
            z = torch.randn(N, N, device="cuda", dtype=dtype)
            for _ in range(3): _ = z @ z
            torch.cuda.synchronize(); t0 = time.time()
            for _ in range(10): _ = z @ z
            torch.cuda.synchronize()
            return (time.time() - t0) * 1000
        f32, f16 = bench(torch.float32), bench(torch.float16)
        ratio = f32 / f16
        detail = f"fp32 {f32:.0f} ms vs fp16 {f16:.0f} ms  ({ratio:.2f}x)"
        if ratio > 1.5:
            warn("fp16 speedup", detail + " -- unexpectedly fast for Pascal; is this really a P4?")
        else:
            info("fp16 speedup", detail + " -- expected: no Tensor Cores, fp16 saves memory not time")
    except Exception as e:
        warn("fp16 benchmark", str(e))

print("\n== result ==")
if fails:
    print(f"  \033[31m{len(fails)} critical check(s) failed:\033[0m {', '.join(fails)}")
    print("  See the gpu-cuda-checks skill (silent-CPU-fallback trap) and deepln-setup for repair steps.")
    sys.exit(1)
if warns:
    print(f"  \033[33mall critical checks passed, {len(warns)} warning(s):\033[0m {', '.join(warns)}")
else:
    print("  \033[32mall checks passed -- this box really is running CUDA work on the GPU\033[0m")
sys.exit(0)
PYEOF
exit $?
