

```markdown
# CPU-Perf

CPU-Perf 是一个用于 **测试指定负载程序 CPU 行为** 的实验脚本集合。

该项目主要用于在 Linux 环境下，通过 cgroup 对负载程序施加资源限制，
并在运行过程中采集 CPU 使用率和 perf 性能指标，用于分析不同负载强度、
资源限制条件下程序的 CPU 行为表现。

当前版本仅支持对 **用户显式提供的负载脚本** 进行测试，
主要用于实验验证和性能对比场景。

---

## 项目用途


- 在 CPU / 内存受限条件下，某个负载程序的运行表现如何
- 不同负载强度变化时，CPU 使用率和指令级指标的变化情况
- 在可控环境中，对实验结果进行重复测试和采集

---

## 当前限制

请注意，本项目目前存在以下限制：

- 仅支持测试 **给定的负载程序脚本**
- 不支持自动注入任意二进制程序
- 不支持多负载并发调度
- 不包含完整的基准负载库

这些能力将在后续版本中逐步完善。

---

## 目录结构说明

```

CPU-Perf/
├── collector.sh
│   主入口脚本，负责参数解析与实验流程控制
│
├── agent_executor.sh
│   核心执行脚本，负责：
│   - cgroup 创建与资源限制配置
│   - perf 监控启动与停止
│   - CPU 使用率采集进程管理
│   - 负载程序执行与清理
│
├── cpuUsages.sh
│   CPU 使用率采样脚本，基于 sar 定期采集数据
│
├── mock_load_script.sh
│   示例负载脚本，用于 CPU 压力测试
│
└── README.md

````

---

## 运行环境要求

- Linux 系统（CentOS / Ubuntu）
- bash
- perf
- sysstat（sar）
- cgroup-tools
- 需要具备 sudo 权限

---

## 使用方式

### 示例：测试给定负载程序

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
````

其中，`--upload-file-path` 指定需要被测试的负载脚本。

---

## 输出结果

实验结束后将生成一个 JSON 文件，内容包括：

* 实验基本信息（实验 ID、运行时间等）
* perf 采集的 CPU 指标
* CPU 使用率时间序列
* 负载程序的标准输出与错误输出

该结果可用于后续的数据分析或绘图处理。

---

## 说明

本项目更偏向实验工具与脚本集合，主要用于系统性能实验和研究场景。
如果需要通用化的基准测试能力，需要在此基础上进一步扩展。

