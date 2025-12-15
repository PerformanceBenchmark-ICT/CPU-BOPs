```markdown
# CPU-Perf

CPU-Perf 是一个基于 Linux 的 CPU 性能测试与监控框架，  
**用于在资源隔离（cgroup）条件下，对指定负载程序（workload）进行性能测试与运行状态采集**，并生成结构化实验结果。

当前版本主要面向 **给定的负载程序** 进行测试，用于评估不同资源限制与负载强度下的 CPU 行为表现，
适用于系统性能实验、资源控制评估以及科研环境中的可重复测试。

---

## 功能特性

- **负载程序性能测试**
  - 对指定负载程序进行 CPU 性能与运行状态测试
- **CPU / 内存资源隔离**
  - 基于 Linux cgroup，对负载程序施加 CPU 与内存限制
- **性能监控**
  - 使用 `perf` 采集 CPU 指令级性能指标
  - 使用 `sar` 定期采样 CPU 使用率
- **统一实验调度**
  - 提供统一入口脚本，集中管理实验参数与执行流程
- **结构化结果输出**
  - 自动汇总实验数据并生成 JSON 结果文件，便于后续分析

---

## 项目结构

```

CPU-Perf/
├── collector.sh           # 主入口脚本，负责参数解析与实验调度
├── agent_executor.sh      # 核心执行器：cgroup 配置、perf / CPU 监控、资源清理
├── cpuUsages.sh           # CPU 使用率采集脚本（基于 sar）
├── mock_load_script.sh    # 示例负载脚本（CPU 压力测试）
└── README.md

````

---

## 设计说明

CPU-Perf 的核心设计目标是：  
**在可控资源环境下，对负载程序的 CPU 行为进行可重复测试与量化分析。**

整体执行流程如下：

1. **collector.sh**
   - 解析用户输入的实验参数
   - 将规范化后的参数传递给执行器

2. **agent_executor.sh**
   - 创建并配置 CPU / 内存 cgroup
   - 启动性能监控：
     - 使用 `perf stat` 采集 CPU 指令级指标
     - 使用 `sar` 采样 CPU 使用率
   - 在 cgroup 约束下启动负载程序
   - 结束负载与监控进程
   - 汇总所有实验数据并生成 JSON 结果文件

3. **cpuUsages.sh**
   - 以固定时间间隔记录 CPU 使用率数据

4. **负载程序**
   - 当前版本仅支持测试 **用户显式指定的负载脚本**
   - 项目中提供了一个示例 CPU 负载脚本用于测试验证

---

## 当前限制说明（Important）

⚠️ **当前版本为阶段性实现，存在以下限制：**

- 本工具 **用于测试负载程序本身的 CPU 行为**
- 当前仅支持对 **给定的、用户提供的负载脚本** 进行测试
- 暂不支持：
  - 通用程序自动注入
  - 多负载并发调度
  - 复杂应用级工作负载建模

上述能力将在后续版本中逐步扩展。

---

## 运行环境依赖

- Linux 系统（已在 CentOS / Ubuntu 测试）
- `bash`
- `perf`
- `sysstat`（用于 `sar`）
- `cgroup-tools`
- 具备 `sudo` 权限（用于 cgroup 与 perf）

---

## 安装方式

```bash
git clone https://github.com/PerformanceBenchmark-ICT/CPU-Perf.git
cd CPU-Perf
chmod +x *.sh
````

---

## 使用示例

### 基本用法（测试给定负载程序）

```bash
./collector.sh \
  --id=test001 \
  --upload-file-path=./mock_load_script.sh \
  --output-path=/tmp/test001.json \
  --cpu-limit-pct=80 \
  --mem-limit-pct=100 \
  --monitor-duration=30s \
  --collect-frequency=1s \
  --start-load-pct=10 \
  --end-load-pct=50 \
  --step-pct=10
```

其中 `--upload-file-path` 指定需要测试的负载脚本。

---

## 参数说明

| 参数                    | 说明             |
| --------------------- | -------------- |
| `--id`                | 实验唯一标识         |
| `--upload-file-path`  | 被测试的负载程序脚本路径   |
| `--output-path`       | 实验结果 JSON 输出路径 |
| `--cpu-limit-pct`     | CPU 使用上限（百分比）  |
| `--mem-limit-pct`     | 内存使用上限（百分比）    |
| `--monitor-duration`  | 监控持续时间         |
| `--collect-frequency` | CPU 使用率采样间隔    |
| `--start-load-pct`    | 初始负载强度         |
| `--end-load-pct`      | 最终负载强度         |
| `--step-pct`          | 负载递增步长         |

---

## 输出结果说明

实验结束后将生成一个 JSON 文件，包含：

* 实验元数据（实验 ID、时间信息等）
* CPU 指令级性能指标（来自 `perf`）
* CPU 使用率时间序列数据
* 实验运行时长
* 负载程序的标准输出与错误日志

---

## 适用场景

* 给定负载程序的 CPU 性能测试
* 资源隔离与限额效果评估
* 系统级性能实验
* 基础设施性能分析
* 科研实验中的可重复性能测试

---

## 注意事项

* 运行前请确保系统支持并正确配置 cgroup
* 需要足够权限以执行 `perf` 与 cgroup 相关操作
* 自定义负载脚本建议正确处理信号，以确保实验可被正常终止

```

---
