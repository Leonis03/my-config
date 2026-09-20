# 通过 SSH 跑远程长任务的踩坑

> 从建模项目的云端算力笔记里抽出来的通用部分。原文绑定具体节点和脚本名，这里只保留换个项目也成立的内容。
>
> 具体机器的连接配置见 [`../agent/skills/deepln-setup/`](../agent/skills/deepln-setup/)（DeepLN 租用 GPU 节点）。

---

## 1. `nohup … &` 套在 `ssh` 里时，ssh 自己可能不返回

```bash
ssh node 'nohup long_job.py > log 2>&1 &'      # ← 可能一直挂着不返回
```

后台进程虽然起来了，但 `ssh` 在等远端那条管道关闭。子进程继承了 stdout/stderr，管道就一直不关。

**两种解法：**

```bash
# A. 给 ssh 套超时（最省事）
timeout 10 ssh node 'nohup long_job.py > log 2>&1 &'

# B. 驱动逻辑写成脚本推上去（复杂任务推荐）
scp run.sh node:/data/
ssh node 'cd /data && nohup ./run.sh > log 2>&1 &'
```

看进度用**独立的短连接**，不要开着前台等：

```bash
ssh node 'tail -20 /data/log'
```

---

## 2. `pkill -f '<脚本名>'` 会连发起它的那层 shell 一起杀掉

**症状**：命令返回 **255**，看起来像 SSH 连接失败，实际是你把自己的远端 shell 杀了。

原因很直白：`ssh node '... long_job.py ...'` 会让远端 shell 的**命令行里就包含 `long_job.py` 这个字符串**，于是 `-f`（匹配完整命令行）把它一并命中。

用 `pgrep -af` 先看会匹配到谁，再决定要不要杀：

```bash
pgrep -af 'long_job.py'
```

**这个现象在本机也能复现**，而且会连 AI agent 自己的包装 shell 一起匹配上——agent 执行命令时，模式串就写在那层 shell 的命令行里。

**收窄模式**，让它只匹配真正的进程：

```bash
pkill -f 'python long_job'      # ✓ 带上解释器名
pkill -f '[l]ong_job.py'        # ✓ 字符类技巧，模式本身不自匹配
```

只是想临时让出 CPU 的话不必真杀：

```bash
pkill -STOP -f 'python long_job'    # 暂停
pkill -CONT -f 'python long_job'    # 恢复
```

---

## 3. 线程数必须在 shell 里设，不能在 Python 里设

```python
import os
os.environ["OMP_NUM_THREADS"] = "1"   # ✗ 太晚了
import numpy as np
```

模块顶部 `import numpy` 时 OpenBLAS 的线程池**已经按默认值初始化完毕**，之后改环境变量不再生效。`fork` 出来的每个 worker 都带着满线程的 BLAS，互相抢核。

**实测代价**（64 核节点，48 个 worker）：开出 **3077 个线程**，load average 峰值 129，同一批任务从 **3 秒劣化到 680 秒——227 倍**。

**正确做法**是在 shell 里设，让解释器启动前就生效：

```bash
OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  python job.py -j 24
```

> `-j` 的值要按节点的实际核数给，不要照抄别的机器。换节点忘了改这个数是常见失误。

---

## 4. 「实际核数」不是 `nproc`——容器里 CPU 和内存都是虚标的

上一节说 `-j` 要按实际核数给。**问题是 `nproc` 报的不是实际核数。**

租用的 GPU / 算力节点几乎都是容器。`nproc`、`/proc/cpuinfo`、`/proc/meminfo` 读的是**宿主机**的值，而你真正能用的是 **cgroup 配额**。两者可以差一个数量级：

| 项 | `nproc` / `MemTotal` 报的 | cgroup 实际配额 | 倍数 |
| :--- | :--- | :--- | ---: |
| CPU | 64 | **8.83 核** | 7.2x |
| 内存 | 125.8 GB | **18 GiB** | 7.0x |

（2026-09-20 实测于某 P4 节点，与 2026-05 记录的 `~8.83 核` 一致。）

**一行查清楚**（cgroup v2）：

```bash
awk '{printf "CPU: %.2f 核\n", $1/$2}' /sys/fs/cgroup/cpu.max
awk '{printf "MEM: %.1f GiB\n", $1/1073741824}' /sys/fs/cgroup/memory.max
```

cgroup v1 的节点换成：

```bash
awk '{printf "CPU: %.2f 核\n", $1/100000}' /sys/fs/cgroup/cpu/cpu.cfs_quota_us
awk '{printf "MEM: %.1f GiB\n", $1/1073741824}' /sys/fs/cgroup/memory/memory.limit_in_bytes
```

> `cpu.max` 第一个字段是 `max` 时表示不限制，此时 `nproc` 才是真的。

**两种虚标的后果完全不同，内存那条更凶：**

- **CPU 超配只是慢。** 按 64 开进程，8.83 核的配额被互相抢，就是上一节那个「227 倍」。
- **内存超配是直接被杀。** 按 125 GB 规划的批量任务在 18 GiB 上会触发 OOM Kill，而且日志里常常只留一个退出码 **137**，看起来像「任务莫名其妙没了」。`dmesg | grep -i oom` 才看得到真相。

**换节点时这两个数都要重新量**，不同机型配额差别很大——同一家的另一台曾是 `nproc` 256 / 实际 24 核。照抄上一台的 `-j` 要么白扔算力，要么打爆。

---

## 5. 重定向到文件必须带 `PYTHONUNBUFFERED=1`

不加的话进程结束前 `tail` 看到的是**空文件**（4 KB 块缓冲），极易误判成"脚本挂了"。

```bash
PYTHONUNBUFFERED=1 nohup uv run --python 3.12 job.py > log 2>&1 &
```

`uv run` **不接受 `-u`**，只能用这个环境变量。详见 [`python/README.md`](python/README.md)。

---

## 6. 别用嵌套 heredoc 把源码传上去

```bash
ssh node '... <<EOF
print(f"{"x":>9}")
EOF'
```

外层 shell 会先吃掉一层引号，f-string 里的内层引号被剥掉就变成语法错误——**这个坑与 Python 版本无关**，看起来却很像版本问题，容易查错方向。

**稍微复杂的脚本一律写成文件 `scp` 上去再跑。**

---

## 7. 跨平台数值差异：冻结数字前要钉死平台

同一份代码、同一组 seed，WSL2 上 272.388 s、Windows 上 272.571 s——**0.07%** 的差异。根源是 `numpy.linalg.eigh` 在不同 BLAS 实现下特征向量有微小差异。

numpy 的 wheel 自带 OpenBLAS 并**按 CPU 运行时分派内核**，所以 AMD Zen 和 Intel Broadwell 上末位可能分叉。

- 要引用的数字，**记清是哪台机器、什么 Python 和 numpy 版本跑的**
- 消融/对照用**配对比较**（同一批 seed 的 Δ），配对 Δ 对平台不敏感
- 换算法或换 seed 区间后，**重测一次再引用**，不要外推

---

## 相关

- [`python/README.md`](python/README.md) —— urllib 代理绕过、f-string 引号规则
- [`../agent/skills/deepln-setup/`](../agent/skills/deepln-setup/) —— DeepLN 云端 GPU 的连接与环境配置（任意卡型）
- [`../agent/skills/gpu-cuda-checks/`](../agent/skills/gpu-cuda-checks/) —— CUDA 冒烟测试与静默回落 CPU 的排查
