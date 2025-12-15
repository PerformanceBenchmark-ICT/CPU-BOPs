#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C



# 默认值
CPU_LIMIT_PCT="100"
MEM_LIMIT_PCT="100"
MONITOR_DURATION="60s"
COLLECT_FREQUENCY="1s"
START_LOAD_PCT="0"
END_LOAD_PCT="0"
STEP_PCT="0"

# --- 进程清理函数 (与 V6 相同) ---
cleanup() {
  echo "Cleaning up all monitor processes (trap)..."
  
# 1. perf (修正版：先 SIGINT 刷出缓存，再 KILL)
  if [[ -n "${PERF_PID:-}" ]] && kill -0 "$PERF_PID" 2>/dev/null; then
    echo "Stopping perf monitor (SIGINT) to flush buffers..."
    
    # 发送 SIGINT (也就是 Ctrl+C)，perf 收到这个信号会打印 Summary 并刷新缓冲区
    PGID_P=$(ps -o pgid= -p "$PERF_PID" | tr -d ' ')
    if [[ -n "$PGID_P" ]]; then 
        kill -INT -"$PGID_P" 2>/dev/null || true
    else 
        kill -INT "$PERF_PID" 2>/dev/null || true
    fi
    
    # 给它 2 秒钟时间处理后事 (写日志)
    sleep 2
    
    # 如果还活着，再强制杀
    if kill -0 "$PERF_PID" 2>/dev/null; then
        echo "Perf still alive, sending SIGKILL..."
        if [[ -n "$PGID_P" ]]; then kill -KILL -"$PGID_P" 2>/dev/null || true; else kill -KILL "$PERF_PID" 2>/dev/null || true; fi
    fi
  fi

  # 2. cpuUsages
  if [[ -n "${CPU_PID:-}" ]] && kill -0 "$CPU_PID" 2>/dev/null; then
    echo "Sending SIGINT (polite) to cpuUsages group GID $CPU_PID..."
    PGID_C=$(ps -o pgid= -p "$CPU_PID" | tr -d ' ')
    if [[ -n "$PGID_C" ]]; then kill -INT -"$PGID_C" 2>/dev/null || true; else kill -INT "$CPU_PID" 2>/dev/null || true; fi
    sleep 2 # 等待 awk 刷新
    if kill -0 "$CPU_PID" 2>/dev/null; then
      echo "cpuUsages GID $CPU_PID did not exit, sending SIGKILL."
      if [[ -n "$PGID_C" ]]; then kill -KILL -"$PGID_C" 2>/dev/null || true; else kill -KILL "$CPU_PID" 2>/dev/null || true; fi
    fi
  fi
  
  # 3. 负载
  if [[ -n "${LOAD_PID:-}" ]] && kill -0 "$LOAD_PID" 2>/dev/null; then
    echo "Cleaning up lingering load process GID $LOAD_PID (sending SIGTERM)..."
    PGID_L=$(ps -o pgid= -p "$LOAD_PID" | tr -d ' ')
    if [[ -n "$PGID_L" ]]; then 
        kill -TERM -"${PGID_L}" 2>/dev/null || true;
    else 
        kill -TERM "$LOAD_PID" 2>/dev/null || true; 
    fi
    for _ in {1..20}; do sleep 0.1; kill -0 "$LOAD_PID" 2>/dev/null || break; done
    if kill -0 "$LOAD_PID" 2>/dev/null; then
      echo "Load still alive, sending SIGKILL..."
      if [[ -n "$PGID_L" ]]; then kill -KILL -"$PGID_L" 2>/dev/null || true; else kill -KILL "$LOAD_PID" 2>/dev/null || true; fi
    fi
  fi

  # 4. cgroup
  if [[ -n "${CG:-}" ]]; then
    echo "Cleaning up cgroup: $CG"
    sudo cgdelete -r -g cpu,memory:"$CG" >/dev/null 2>&1 || echo "Warning: cgdelete failed."
  fi
}
# --- 绑定 trap ---
trap cleanup EXIT INT TERM

# --- 参数解析 (与 V6 相同) ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    # ... (所有参数解析保持不变) ...
    --id) ID="$2"; shift 2;;
    --id=*) ID="${1#*=}"; shift;;
    --upload-file-path) UPLOAD_FILE="$2"; shift 2;;
    --upload-file-path=*) UPLOAD_FILE="${1#*=}"; shift;;
    --output-path) OUTPUT_PATH="$2"; shift 2;;
    --output-path=*) OUTPUT_PATH="${1#*=}"; shift;;
    --cpu-limit-pct) CPU_LIMIT_PCT="$2"; shift 2;;
    --cpu-limit-pct=*) CPU_LIMIT_PCT="${1#*=}"; shift;;
    --mem-limit-pct) MEM_LIMIT_PCT="$2"; shift 2;;
    --mem-limit-pct=*) MEM_LIMIT_PCT="${1#*=}"; shift;;
    --monitor-duration) MONITOR_DURATION="$2"; shift 2;;
    --monitor-duration=*) MONITOR_DURATION="${1#*=}"; shift;;
    --collect-frequency) COLLECT_FREQUENCY="$2"; shift 2;;
    --collect-frequency=*) COLLECT_FREQUENCY="${1#*=}"; shift;;
    --start-load-pct) START_LOAD_PCT="$2"; shift 2;;
    --start-load-pct=*) START_LOAD_PCT="${1#*=}"; shift;;
    --end-load-pct) END_LOAD_PCT="$2"; shift 2;;
    --end-load-pct=*) END_LOAD_PCT="${1#*=}"; shift;;
    --step-pct) STEP_PCT="$2"; shift 2;;
    --step-pct=*) STEP_PCT="${1#*=}"; shift;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

# --- 基础校验 (与 V6 相同) ---
if [[ -z "${ID:-}" || -z "${UPLOAD_FILE:-}" || -z "${OUTPUT_PATH:-}" ]]; then
  echo "FATAL: missing --id / --upload-file-path / --output-path" >&2
  exit 1
fi
if [[ ! -f "$UPLOAD_FILE" ]]; then
  echo "FATAL: Workload script not found: $UPLOAD_FILE" >&2
  exit 1
fi

# --- 时间解析 (与 V6 相同) ---
to_seconds() {
  local s="$1" unit val
  if [[ "$s" =~ ^([0-9]+)([smh])$ ]]; then
    val="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"
  else
    val="$s"; unit="s"
  fi
  case "$unit" in
    s) echo "$val" ;;
    m) echo $((val*60)) ;;
    h) echo $((val*3600)) ;;
    *) echo "$val" ;;
  esac
}
to_millis() { echo $(( $(to_seconds "$1") * 1000 )); }


# --- [!! 关键修改 1: 架构检测提前 !!] ---
echo "Detecting system architecture for filenames..."
ARCH_RAW=$(uname -m) # 例如 x86_64 或 aarch64
ARCH_NAME=""
if [[ "$ARCH_RAW" == "x86_64" ]]; then
    ARCH_NAME="x86"
elif [[ "$ARCH_RAW" == "aarch64" ]]; then
    ARCH_NAME="arm"
else
    ARCH_NAME="$ARCH_RAW" # 保留未知架构的原始名称
fi


# --- [!! 关键修改 2: 路径定义使用 $ARCH_NAME !!] ---
OUT_DIR="$(dirname "$(readlink -f "$OUTPUT_PATH")")"
mkdir -p "$OUT_DIR"
SAFE_ID="$(printf '%s' "$ID" | tr -c 'A-Za-z0-9_.-' '_')"

BOP_FILE="$OUT_DIR/bops_${ARCH_NAME}_${SAFE_ID}.txt"
CPU_FILE="$OUT_DIR/cpuUsage_${ARCH_NAME}_${SAFE_ID}.txt"
STDOUT_FILE="$OUT_DIR/stdout_${ARCH_NAME}_${SAFE_ID}.log"
STDERR_FILE="$OUT_DIR/stderr_${ARCH_NAME}_${SAFE_ID}.log"
RUNTIME_FILE="$OUT_DIR/runtime_${ARCH_NAME}_${SAFE_ID}.txt"

rm -f "$BOP_FILE" "$CPU_FILE" "$STDOUT_FILE" "$STDERR_FILE" "$RUNTIME_FILE"
echo "# started on $(date '+%F %T')" > "$BOP_FILE"

CG="task_${ID}"

# --- Cgroup 设置 (与 V6 相同) ---
echo "Setting up cgroup: $CG..."
sudo cgcreate -g cpu,memory:"$CG" >/dev/null 2>&1 || true
CPU_PERIOD_US=100000
NPROC="$(nproc || echo 1)"
if ! [[ "$CPU_LIMIT_PCT" =~ ^[0-9]+$ ]]; then CPU_LIMIT_PCT=100; fi
((CPU_LIMIT_PCT<1))  && CPU_LIMIT_PCT=1
((CPU_LIMIT_PCT>100))&& CPU_LIMIT_PCT=100
CPU_QUOTA_US=$(
  awk -v p="$CPU_PERIOD_US" -v pct="$CPU_LIMIT_PCT" -v nc="$NPROC" \
      'BEGIN{q=int(p*(pct/100.0)*nc); if(q<1000)q=1000; print q;}'
)
sudo cgset -r cpu.cfs_quota_us="$CPU_QUOTA_US" "$CG"
MEMTOTAL_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
if [[ "$MEMTOTAL_KB" -gt 0 ]]; then
  MEM_LIMIT_BYTES=$(
    awk -v kb="$MEMTOTAL_KB" -v pct="$MEM_LIMIT_PCT" \
        'BEGIN{print int(kb*1024*(pct/100.0));}'
  )
  sudo cgset -r memory.limit_in_bytes="$MEM_LIMIT_BYTES" "$CG"
else
  MEM_LIMIT_BYTES=-1
fi
echo "Cgroup setup complete: CPU ${CPU_LIMIT_PCT}% (${CPU_QUOTA_US} us), Mem ${MEM_LIMIT_PCT}% (${MEM_LIMIT_BYTES} bytes)"


# --- [!! 关键修改 3: 重用 $ARCH_RAW (V10 逻辑) !!] ---
echo "Configuring perf events for architecture: $ARCH_RAW ($ARCH_NAME)"

# 声明变量
declare ORIG_EVENTS
declare FLOPS_EVENTS
declare FINAL_EVENTS # 最终的事件列表

if [[ "$ARCH_RAW" == "x86_64" ]]; then
    echo "Architecture: x86_64 (Intel/AMD). Using x86 perf events."
    
    # 1. x86 原始事件 (BOPs)
    ORIG_EVENTS="uops_executed.core,mem_inst_retired.all_stores,mem_inst_retired.all_loads,br_inst_retired.all_branches"
    
    # 2. x86 FLOPs 事件
    FLOPS_EVENTS="fp_arith_inst_retired.scalar_double,fp_arith_inst_retired.scalar_single,fp_arith_inst_retired.128b_packed_double,fp_arith_inst_retired.128b_packed_single,fp_arith_inst_retired.256b_packed_double,fp_arith_inst_retired.256b_packed_single,fp_arith_inst_retired.512b_packed_double,fp_arith_inst_retired.512b_packed_single"

    # 合并 x86 列表
    FINAL_EVENTS="${ORIG_EVENTS},${FLOPS_EVENTS}"

elif [[ "$ARCH_RAW" == "aarch64" ]]; then
    echo "Architecture: aarch64 (ARM/Kunpeng). Using ARM core events only."
    
    # 1. ARM 核心事件 (BOPs), 基于 full_perf_list (1).txt
    ORIG_EVENTS="inst_retired,br_retired,l1d_cache_refill,l1d_cache_wb"
    
    # 2. ARM FLOPs 事件
    FLOPS_EVENTS="" # (根据您的要求)

    # 仅使用核心事件
    FINAL_EVENTS="${ORIG_EVENTS}"

else
    echo "FATAL: Unsupported architecture: $ARCH_RAW. Only x86_64 and aarch64 are supported." >&2
    exit 3
fi

# --- 启动监控 (使用动态设置的变量) ---
echo "Starting monitors (perf, cpuUsages)..."
START_TS_NANO=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000") 
INTERVAL_MS="$(to_millis "$COLLECT_FREQUENCY")"

echo "Starting perf with events for $ARCH_NAME..."
echo "Using event list: ${FINAL_EVENTS}"
setsid perf stat \
  -e "${FINAL_EVENTS}" \
  -a -I "$INTERVAL_MS" -x , \
  >/dev/null 2>>"$BOP_FILE" &
PERF_PID=$!

if [[ -x ./cpuUsages.sh ]]; then
  setsid ./cpuUsages.sh >"$CPU_FILE" 2>/dev/null &
  CPU_PID=$!
else
  # [!! 关键修复 (V15) !!]
  # 1. 确保 sysstat (sar) 已安装
  if ! command -v sar &> /dev/null; then
    echo "FATAL: 'sysstat' (sar) is missing. Please install it!" >&2
    # 立即杀死已启动的 perf，避免僵尸进程
    if [[ -n "${PERF_PID:-}" ]]; then kill -KILL "$PERF_PID" 2>/dev/null || true; fi
    exit 5
  fi

  # 2. 启动 sar 进程 (替代 while loop)
  # setsid: 放入新会话，方便清理
  # stdbuf -oL: 强制行缓冲，确保实时输出
  # sar -u 1: 每秒输出一次 CPU 使用率
  # awk: 格式化输出为 "YYYY-MM-DD HH:MM:SS CPU Usage: XX.X%"
  #      (注意：这里使用 date 命令获取当前时间，因为 sar 的时间戳格式可能不统一)
  setsid stdbuf -oL sar -u 1 | awk -v date_cmd="date '+%Y-%m-%d %H:%M:%S'" \
    'NR>3 && $NF ~ /[0-9.]+/ { 
       cmd = date_cmd; cmd | getline ts; close(cmd);
       usage = 100 - $NF; 
       printf "%s CPU Usage: %.2f%%\n", ts, usage;
       fflush(); 
    }' >"$CPU_FILE" 2>/dev/null &
  
  CPU_PID=$!
fi




# --- 启动负载 (与 V6 相同) ---
echo "Starting workload: $UPLOAD_FILE"
LOAD_CMD=(bash "$UPLOAD_FILE" "--start-load-pct=$START_LOAD_PCT" "--end-load-pct=$END_LOAD_PCT" "--step-pct=$STEP_PCT")

setsid sudo cgexec -g cpu,memory:"$CG" "${LOAD_CMD[@]}" \
  >"$STDOUT_FILE" 2>"$STDERR_FILE" &
LOAD_PID=$!

# --- [修改] 分离负载时间和监控总时间 ---
LOAD_SEC="$(to_seconds "$MONITOR_DURATION")"
RUN_SEC=$((LOAD_SEC + 5))  # 强行给监控续命 5 秒 (Buffer)
echo "All processes launched. Load will run for ${LOAD_SEC}s, Monitor will run for ${RUN_SEC}s..."

START_TS=$(date +%s)
WORK_DONE=0

# --- 主循环 (V16 - 强制跑满时长) ---
LOAD_ALIVE=1  # 标记负载是否还活着

while :; do
# 1. 检查时间
  NOW=$(date +%s)
  ELAPSED=$((NOW-START_TS))
  
  # [新增逻辑 A] 时间到了 LOAD_SEC (30s)：只杀负载，不退循环
  if (( ELAPSED >= LOAD_SEC )) && [[ "$LOAD_ALIVE" -eq 1 ]]; then
    echo ">>> Load duration reached (${LOAD_SEC}s). Stopping workload only..."
    PGID=$(ps -o pgid= -p "$LOAD_PID" | tr -d ' ')
    if [[ -n "$PGID" ]]; then
      kill -TERM -"${PGID}" 2>/dev/null || true
    else
      kill -TERM "$LOAD_PID" 2>/dev/null || true
    fi
    wait "$LOAD_PID" 2>/dev/null || true
    LOAD_ALIVE=0
    # 注意：这里没有 break，循环继续，监控继续跑
  fi

  # [修改逻辑 B] 时间到了 RUN_SEC (35s)：退出循环，触发 cleanup 杀监控
  if (( ELAPSED >= RUN_SEC )); then
    echo ">>> Total monitor buffer time reached (${RUN_SEC}s). Exiting."
    break
  fi

  # 2. 检查负载状态 (仅做记录，不退出循环)
  if [[ "$LOAD_ALIVE" -eq 1 ]]; then
      if ! kill -0 "$LOAD_PID" 2>/dev/null; then
        echo ">>> Workload finished early at ${ELAPSED}s (Process exited)."
        echo ">>> Continuing to monitor idle system until ${RUN_SEC}s..."
        LOAD_ALIVE=0 # 标记为已死，不再检查
      fi
  fi

  sleep 0.2
done
if [[ "$WORK_DONE" -eq 1 ]]; then
  wait "$LOAD_PID" 2>/dev/null || true
fi

# --- [!! 新增 (V11) !!] 计算并保存总运行时长 ---
echo "Calculating total measured runtime..."

# 从 bops.txt 中提取最后一个时间戳 (字段 1)
# grep -v '^#' 确保我们跳过开头的 "# started on..."
TOTAL_RUNTIME=$(grep -v '^#' "$BOP_FILE" | tail -n 1 | awk -F',' '{print $1}')

if [[ -n "$TOTAL_RUNTIME" ]]; then
    echo "$TOTAL_RUNTIME" > "$RUNTIME_FILE"
    echo "Total measured runtime ($TOTAL_RUNTIME s) saved to $RUNTIME_FILE"
else
    echo "Warning: Could not determine total runtime from $BOP_FILE."
fi

# --- (清理现在由 trap 自动处理) ---


# ----------------------------------------------------
# ... (在 agent_executor.sh 结尾处) ...

# ========================================================
# [新增] 智能数据清洗：根据设定时长自动裁剪多余数据
# ========================================================
echo "Applying smart data trimming for duration: ${LOAD_SEC}s..."

# 1. 清洗 Perf 数据 (基于时间戳过滤)
# 逻辑：保留所有注释行(#开头) + 第一列时间戳 <= (LOAD_SEC + 0.5) 的数据行
if [[ -f "$BOP_FILE" ]]; then
    # 计算阈值 (例如 30 -> 30.5)，防止浮点数微小误差导致丢数据
    TRIM_THRESHOLD=$(awk -v t="$LOAD_SEC" 'BEGIN {print t + 0.5}')
    
    # 创建临时文件进行处理
    awk -F, -v limit="$TRIM_THRESHOLD" '
        /^#/ { print; next }       # 保留 # 开头的注释行
        $1 <= limit { print }      # 保留时间戳在范围内的数据
    ' "$BOP_FILE" > "${BOP_FILE}.tmp" && mv "${BOP_FILE}.tmp" "$BOP_FILE"
    
    echo "-> Trimmed Perf data to <= ${TRIM_THRESHOLD}s."
fi

# 2. 清洗 CPU 数据 (基于行数截断)
# 逻辑：sar -u 1 理论上每秒一行。只保留前 LOAD_SEC 行。
if [[ -f "$CPU_FILE" ]]; then
    # 使用 head -n 截取前 N 行
    # 注意：如果 cpuUsages.sh 启动慢了导致行数不足，head 也会保留所有现有行，不会报错
    head -n "$LOAD_SEC" "$CPU_FILE" > "${CPU_FILE}.tmp" && mv "${CPU_FILE}.tmp" "$CPU_FILE"
    
    echo "-> Trimmed CPU data to first ${LOAD_SEC} lines."
fi

# 3. 修正 Runtime 文件
# 因为我们切掉了尾巴，runtime 应该被修正为我们设定的目标时长，或者清洗后的最后一行时间
if [[ -f "$BOP_FILE" ]]; then
    # 从清洗后的文件中提取最后一行的时间戳
    REAL_FINAL_TIME=$(grep -v '^#' "$BOP_FILE" | tail -n 1 | awk -F',' '{print $1}')
    if [[ -n "$REAL_FINAL_TIME" ]]; then
        echo "$REAL_FINAL_TIME" > "$RUNTIME_FILE"
        echo "-> Updated runtime file to: $REAL_FINAL_TIME"
    fi
fi

# ========================================================

echo "Success! All logs written to $OUT_DIR"
exit 0