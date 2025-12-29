# CPU-BOPs

CPU-BOPs 是一组用于在 Linux CPU 平台上测量负载程序运行周期消耗的BOPs（Basic Operations，基本操作数）指标 的脚本工具。

该项目通过非入侵的方式，监测被测量的应用程序的运行生命周期，按照指定频率采集BOPs指标关联的指令级的事件操作数，通过计算，最终计算出BOPs值。

## 环境依赖 (Prerequisites)
为了确保 CPU-BOPs 能够正常运行，宿主机必须满足以下软硬件要求。

操作系统与权限
操作系统：Linux 
内核版本：支持 Cgroup v1
权限要求：拥有 root 权限 或 sudo 权限


脚本运行依赖以下系统工具包，请根据发行版进行安装：

| 工具名称 | 作用 | 对应软件包 (CentOS/RHEL) | 对应软件包 (Ubuntu/Debian) |
| :--- | :--- | :--- | :--- |
| **perf** | 采集硬件性能事件 (BOPs) | `perf` | `linux-tools-$(uname -r)` |
| **cgroup-tools** | 管理资源隔离组 (`cgcreate`) | `libcgroup-tools` | `cgroup-tools` |


## 项目解决的问题

在系统性能实验与算力度量中，常常需要回答以下问题：
* 不同的CPU平台上如何从用户视角实现算力度量的指标统一？
* 不同的CPU平台上如何从用户视角实现算力的单一计量？


CPU-BOPs 提供了一种 **轻量、可复现、面向真实负载的实验执行与采集方案**



## 虚拟机访问权限开通
在虚拟机上统计BOPS所用到的工具，需要打开虚拟机直通物理机的开关，开关打开之后，需要重启物理机上的虚拟机才能生效，步骤如下：

1.在openstack控制节点执行：

openstack server show <云主机uuid> |grep OS-EXT-SRV-ATTR:instance_name

得到输出

| OS-EXT-SRV-ATTR:instance_name       | instance-00000c3c


然后到虚拟机所在的物理机上执行：virsh edit instance-00000c3c

2. 找到这个 <cpu mode='host-passthrough'>

3.步骤2中红色字体表示的值即为需要修改的值。即cpu mode 改成 host-passthrough

4.重启这个虚拟机,执行如下命令：

   "# virsh  reboot  <虚拟机ID或名称>"
   

注：以上操作步骤只是开通虚拟机的权限，对宿主机没有影响。


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



## 目录结构

```text
CPU-BOPs/
├── collector.sh
│   实验入口脚本，负责参数解析与执行调度
│
├── agent_executor.sh
│   核心执行器：
│   - cgroup 配置
│   - 负载进程管理与清理
│
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
| `--monitor-duration`  | 负载**最大允许运行时间（timeout）** | 60s |
| `--collect-frequency` |  采样间隔     | 1s  |

> 说明：
>
> * `monitor-duration` 表示 **最长运行时间**。
> * 如果负载提前结束，实验会提前进入“空闲监控阶段”。

---

---

## 使用示例

### 示例 1：测试一个真实负载（推荐用法）

```bash
bash collector.sh \
  --id=test_min \
  --upload-file-path=./test.py \
  --output-path=./test_min.json \
  --monitor-duration=30s
```

适用于：

* ELF 二进制
* Python / Shell 脚本
* shebang 可执行脚本

---


```

---

## 输出结果说明

实验结束后，会在输出目录生成多类日志文件，包括：

* BOPs 采样数据
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



























