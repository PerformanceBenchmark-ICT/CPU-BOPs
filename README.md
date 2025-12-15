# CPU-Perf

CPU-Perf 是一组用于测试指定负载程序 CPU 行为的实验脚本。

该项目运行在 Linux 环境下，通过 cgroup 对负载程序施加 CPU / 内存限制，
并在运行过程中采集 CPU 使用率和 perf 指标，用于分析不同资源限制和负载强度下
程序的 CPU 行为表现。

当前版本主要用于测试用户提供的负载脚本，
更偏向实验和验证用途，而不是通用的性能测试工具。

---

## 这个项目解决什么问题

在系统性能实验中，常常需要回答以下问题：

- 某个负载程序在 CPU 受限条件下的运行表现
- 不同负载强度变化时 CPU 使用率的变化情况
- 在可控环境中重复采集实验数据

CPU-Perf 提供了一种相对简单、可复现的方式来完成上述测试。

---

## 当前限制

目前该项目存在以下限制：

- 只能测试用户显式指定的负载脚本
- 不支持直接测试任意二进制程序

后续功能将在此基础上逐步扩展。

---

## 目录结构

```text
CPU-Perf/
├── collector.sh
│   负责参数解析和实验流程控制
│
├── agent_executor.sh
│   负责 cgroup 配置、perf 监控、CPU 使用率采集以及资源清理
│
├── cpuUsages.sh
│   基于 sar 的 CPU 使用率采样脚本
│
├── mock_load_script.sh
│   示例 CPU 负载脚本
│
└── README.md
```




---

## 运行环境

- Linux（CentOS / Ubuntu）
- bash
- perf
- sysstat（sar）
- cgroup-tools
- 需要 sudo 权限

---
| 参数名                 | 含义             |
| ------------------- | -------------- |
| --id                | 实验标识，用于区分不同实验  |
| --upload-file-path  | 被测试的负载脚本路径     |
| --output-path       | 实验结果 JSON 输出路径 |
| --cpu-limit-pct     | CPU 使用上限（百分比）  |
| --mem-limit-pct     | 内存使用上限（百分比）    |
| --monitor-duration  | 实验与监控持续时间      |
| --collect-frequency | CPU 使用率采样间隔    |
| --start-load-pct    | 初始负载强度         |
| --end-load-pct      | 最终负载强度         |
| --step-pct          | 负载强度递增步长       |

## 使用示例

下面的示例展示了如何对一个给定的负载脚本进行测试：

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
upload-file-path 用于指定需要测试的负载脚本。

输出结果
实验结束后会生成一个 JSON 文件，包含：

实验基本信息

perf 采集的 CPU 指标

CPU 使用率时间序列

负载程序的标准输出和错误输出

这些数据可用于后续分析或绘图。

说明
该项目更偏向实验脚本集合，主要用于系统性能测试和研究场景。
如果需要更通用的负载测试能力，需要在此基础上进一步扩展。








