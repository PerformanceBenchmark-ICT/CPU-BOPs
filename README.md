# CPU-BOPs

CPU-BOPs 是一组用于在 Linux CPU 平台上测量负载程序运行周期消耗的BOPs（Basic Operations，基本操作数）指标 的脚本工具。

该项目通过非入侵的方式，监测被测量的应用程序的运行生命周期，按照指定频率采集BOPs指标关联的指令级的事件操作数，通过计算，最终计算出BOPs值。

## 环境依赖 (Prerequisites)

### 1、操作系统权限要求：拥有 root 权限 或 sudo 权限


### 2、脚本运行依赖以下系统工具包，请根据发行版进行安装：

| 工具名称 | 作用 |
| :--- | :--- |
| **perf** | 采集硬件性能事件 (BOPs) |
| **cgroup-tools** | 管理资源隔离组 (`cgcreate`) | 

### 3、如果是物理机，具备以上三点可以直接运行，如果是虚拟机，则需要额外开通以下权限：


在虚拟机上统计BOPS所用到的工具，需要打开虚拟机直通物理机的开关，开关打开之后，需要重启物理机上的虚拟机才能生效，步骤如下：

#### 1.在openstack控制节点执行：

openstack server show <云主机uuid> |grep OS-EXT-SRV-ATTR:instance_name

得到输出

| OS-EXT-SRV-ATTR:instance_name       | instance-00000c3c


然后到虚拟机所在的物理机上执行：virsh edit instance-00000c3c

#### 2.找到这个`<cpu mode='host-passthrough'>`

#### 3.步骤2中红色字体表示的值即为需要修改的值。即cpu mode 改成 host-passthrough

#### 4.重启这个虚拟机,执行如下命令：

   `# virsh  reboot  <虚拟机ID或名称>`
   

注：以上操作步骤只是开通虚拟机的权限，对宿主机没有影响。


## 项目解决的问题

在系统性能实验与算力度量中，常常需要回答以下问题：
* 不同的CPU平台上如何从用户视角实现算力度量的指标统一？
* 不同的CPU平台上如何从用户视角实现算力的单一计量？


CPU-BOPs 提供了一种 **轻量、可复现、面向真实负载的实验执行与采集方案**





## 支持的负载类型

CPU-BOPs支持的负载程序可以是 **Linux环境下任意可执行文件**


## 工具脚本目录结构

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
> * 如果负载提前结束，会直接结束测量。

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



---

##输出结果展示：
bops_x86_test_min.txt：
```
     1.002481419,9268048049,,uops_executed.core,task_test_min,327282121,32.72,,
     1.002481419,1236976338,,mem_inst_retired.all_stores,task_test_min,330838132,33.08,,
     1.002481419,2623043026,,mem_inst_retired.all_loads,task_test_min,335640222,33.56,,
     1.002481419,1695549612,,br_inst_retired.all_branches,task_test_min,340943693,34.10,,
     1.002481419,6335375,,fp_arith_inst_retired.scalar_double,task_test_min,342077198,34.22,,
     1.002481419,0,,fp_arith_inst_retired.scalar_single,task_test_min,340471018,34.06,,
     1.002481419,0,,fp_arith_inst_retired.128b_packed_double,task_test_min,337538359,33.77,,
     1.002481419,0,,fp_arith_inst_retired.128b_packed_single,task_test_min,334720258,33.46,,
     1.002481419,0,,fp_arith_inst_retired.256b_packed_double,task_test_min,331787667,33.17,,
     1.002481419,0,,fp_arith_inst_retired.256b_packed_single,task_test_min,329843284,32.98,,
     1.002481419,0,,fp_arith_inst_retired.512b_packed_double,task_test_min,327931553,32.79,,
     1.002481419,0,,fp_arith_inst_retired.512b_packed_single,task_test_min,325238180,32.52,,

```

Terminal：

{

  "arch": "x86",
  
  "interval": "1s",
  
  "BOPs": 40909915871
  
}



---

## 输出结果说明

实验结束后，会在输出目录生成多类日志文件，包括：

* BOPs 采样数据
* 负载程序的 stdout / stderr
* 实验运行时长信息

这些数据可用于后续分析、建模或绘图。
title按顺序如下：
time,value,unit,event,command,pid,cpu,metric_value,metric_unit
| 列号 | 列名           | 含义                    |
| -- | ------------ | --------------------- |
| 1  | time         | 距离 perf 开始的时间（秒）      |
| 2  | value        | 该事件在该时间窗口内的计数值        |
| 3  | unit         | 单位（硬件事件一般为空）          |
| 4  | event        | PMU 硬件事件名             |
| 5  | command      | 被监控的进程名               |
| 6  | pid          | 进程 PID                |
| 7  | cpu          | 采样发生的 CPU（或 CPU 平均编号） |



---

## 说明

CPU-BOPs 是一个 **面向系统性能测量与研究场景的实验工具**，强调：

* 真实负载可执行
* 行为可复现
* 资源可控
* 数据可分析
























































