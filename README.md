# CPU-BOPs

CPU-BOPs 是一组用于 **在 Linux CPU 平台上测量负载程序 CPU 行为与 BOPs（Basic Operations）指标** 的实验脚本工具。

该项目通过 **cgroup** 对负载程序施加 CPU / 内存资源限制，并在负载运行过程中同步采集：

* CPU 使用率时间序列
* 基于 `perf` 的 BOPs / 指令级统计指标

用于分析 **不同资源限制、不同负载特性** 下程序的 CPU 行为表现。

---

## 项目解决的问题

在系统性能实验与算力度量中，常常需要回答以下问题：

* 某个负载在给定 CPU / 内存限制下的运行行为如何？
* 不同负载强度、不同执行时间窗口下，CPU 使用率和 BOPs 如何变化？
* 如何在可控、可复现的环境中，对真实负载进行统一测量？

CPU-BOPs 提供了一种 **轻量、可复现、面向真实负载的实验执行与采集框架**。

---



## 测量机制说明

为了确保在 **物理机、虚拟机（VM）、Docker 容器以及公有云（ECS/EC2）** 环境下都能获取到有效的硬件计数器数据，本工具目前采用 **System-Wide（全局）采集模式**。
* **工作原理**：
    工具会启动负载程序，并在负载运行的“生命周期窗口”内，统计 **整个操作系统（所有 CPU 核）** 产生的硬件指令数（BOPs/FLOPs）。
    
* **为什么这样做？**
    大多数云环境和虚拟化平台默认 **不支持** 针对“单个进程”的硬件性能计数器透传（vPMU Context Switching）。如果只测单个进程，通常会返回 `<not counted>` 或 `0`。
    使用全局模式 (`perf stat -a`) 是在云环境下获取数据的唯一通用方案。

* **使用建议**：
    为了保证数据准确性，**请在一个“干净”的节点（Exclusive Node）上运行本工具**。


  
## 当前限制

* **不支持 Windows `.exe`**：无法运行 PE 格式文件。
* **不负责语言运行时管理**：如 Java 的 Classpath、Python 的 venv 需要用户提前配置好。
* **架构差异**：不同 CPU 架构（x86 vs ARM）支持的硬件事件不同，工具会自动识别，但指标名称会有差异。

---
## 支持的负载类型

CPU-BOPs **支持任意 Linux 可执行负载**，包括：

* **Linux 原生可执行程序（ELF）**
* **Shell 脚本（`.sh`）**
* **Python 脚本（`.py`）**
* **带 shebang 的可执行脚本**（如 `#!/usr/bin/env python3`）



---


CPU-BOPs 支持在 Linux 环境 下运行并测量以下类型的负载：

1. Linux 原生可执行文件（ELF）

由 C / C++ / Rust / Go 等语言在 Linux 环境下编译生成

文件格式为 ELF

文件名是否包含 .exe 后缀 不影响执行

示例：

gcc fft.c -O2 -o fft


生成的 fft 为 Linux ELF 可执行文件，可直接作为负载运行。

⚠️ 注意：

必须在 Linux 环境下编译生成 ELF 文件

在 Windows 下编译生成的 .exe（PE 格式）无法在 Linux 上运行

2. 脚本类负载

Shell 脚本（.sh）

Python 脚本（.py）

带 shebang 的可执行脚本（如 #!/usr/bin/env python3）

示例：

#!/usr/bin/env python3
while True:
    pass

不支持的负载类型

Windows PE 格式的 .exe 文件

依赖 Windows 内核或 Windows 运行时的程序

这是由于 CPU-BOPs 基于 Linux 内核能力（cgroup、perf），属于操作系统层面的限制。



## 目录结构

```text
CPU-BOPs/
├── collector.sh
│   实验入口脚本，负责参数解析与执行调度
│
├── agent_executor.sh
│   核心执行器：
│   - cgroup 配置
│   - perf / CPU 使用率监控
│   - 负载进程管理与清理
│
├── cpuUsages.sh
│   基于 sar 的 CPU 使用率采样脚本
│
├── mock_load_script.sh
│   示例：CPU 爬坡负载脚本（用于内部/对照实验）
│
└── README.md
```

---


---

## 参数说明

### 必须参数（缺一不可）

| 参数名                  | 含义                   |
| -------------------- | -------------------- |
| `--id`               | 实验标识，用于区分不同实验        |
| `--upload-file-path` | 被测试的负载路径（可执行文件 / 脚本） |
| `--output-path`      | 实验结果输出路径             |

---

### 通用可选参数（真实负载 & 爬坡负载通用）

| 参数名                   | 含义                      | 默认值 |
| --------------------- | ----------------------- | --- |
| `--cpu-limit-pct`     | CPU 使用上限（百分比）           | 100 |
| `--mem-limit-pct`     | 内存使用上限（百分比）             | 100 |
| `--monitor-duration`  | 负载**最大允许运行时间（timeout）** | 60s |
| `--collect-frequency` | CPU 使用率 / perf 采样间隔     | 1s  |

> 说明：
>
> * `monitor-duration` 表示 **最长运行时间**。
> * 如果负载提前结束，实验会提前进入“空闲监控阶段”。

---

### 爬坡负载专用参数（仅对 mock_load_script.sh 有效）

以下参数 **仅在使用示例爬坡负载时生效**，对真实负载不会注入或生效：

| 参数名                | 含义       |
| ------------------ | -------- |
| `--start-load-pct` | 初始负载强度   |
| `--end-load-pct`   | 最终负载强度   |
| `--step-pct`       | 负载强度递增步长 |

---

## 使用示例

### 示例 1：测试一个真实负载（推荐用法）

```bash
bash collector.sh \
  --id=test_min \
  --upload-file-path=./my_workload \
  --output-path=/tmp/test_min.json \
  --monitor-duration=30s
```

适用于：

* ELF 二进制
* Python / Shell 脚本
* shebang 可执行脚本

---

### 示例 2：测试示例 CPU 爬坡负载

```bash
bash collector.sh \
  --id=ramp_test \
  --upload-file-path=./mock_load_script.sh \
  --output-path=/tmp/ramp_test.json \
  --monitor-duration=60s \
  --start-load-pct=10 \
  --end-load-pct=50 \
  --step-pct=10
```

---

## 输出结果说明

实验结束后，会在输出目录生成多类日志文件，包括：

* BOPs / perf 采样数据
* CPU 使用率时间序列
* 负载程序的 stdout / stderr
* 实验运行时长信息

这些数据可用于后续分析、建模或绘图。

---

## 说明

CPU-BOPs 是一个 **面向系统性能测量与研究场景的实验工具**，强调：

* 真实负载可执行
* 行为可复现
* 资源可控
* 数据可分析











