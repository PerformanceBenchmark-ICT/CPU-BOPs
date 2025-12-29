#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

CPU_LIMIT_PCT="100"
MEM_LIMIT_PCT="100"
MONITOR_DURATION="60s"
COLLECT_FREQUENCY="1s"
START_LOAD_PCT="0"
END_LOAD_PCT="0"
STEP_PCT="0"

cleanup() {
  echo ">>> [Cleanup] Triggered at $(date '+%H:%M:%S')..."
  
  if [[ -n "${PERF_PID:-}" ]]; then
    if kill -0 "$PERF_PID" 2>/dev/null; then
      echo "  -> Stopping Perf (SIGINT) to flush buffers..."
      kill -INT "$PERF_PID" 2>/dev/null || true
      for i in {1..30}; do
        kill -0 "$PERF_PID" 2>/dev/null || break
        sleep 0.1
      done
      
      if kill -0 "$PERF_PID" 2>/dev/null; then
         echo "  -> Perf stuck, force killing..."
         kill -KILL "$PERF_PID" 2>/dev/null || true
      fi
    fi
  fi

  echo "  -> Stopping Workload..."
  
  if [[ -n "${LOAD_PID:-}" ]]; then
      sudo kill -TERM "$LOAD_PID" 2>/dev/null || true
  fi

  if [[ -n "${CG:-}" ]]; then
      PROCS_FILE="/sys/fs/cgroup/cpu/${CG}/cgroup.procs"
      if [[ ! -f "$PROCS_FILE" ]]; then
          PROCS_FILE="/sys/fs/cgroup/cpu/${CG}/tasks"
      fi

      if [[ -f "$PROCS_FILE" ]]; then
          PIDS=$(cat "$PROCS_FILE" 2>/dev/null || true)
          
          if [[ -n "$PIDS" ]]; then
              echo "  -> Found lingering processes in Cgroup, Force Killing: $PIDS"
              echo "$PIDS" | xargs -r sudo kill -9 2>/dev/null || true
          fi
      fi
  fi

  if [[ -n "${CG:-}" ]]; then
    echo "  -> Deleting Cgroup: $CG"
    for i in {1..5}; do
        sudo cgdelete -r -g cpu,memory,perf_event:"$CG" >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            break
        fi
        sleep 0.2
        if [[ -f "$PROCS_FILE" ]]; then
              cat "$PROCS_FILE" 2>/dev/null | xargs -r sudo kill -9 2>/dev/null || true
        fi
    done
  fi

  echo ">>> [Cleanup] Done."
}

trap cleanup EXIT INT TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ -z "${ID:-}" || -z "${UPLOAD_FILE:-}" || -z "${OUTPUT_PATH:-}" ]]; then
  echo "FATAL: missing --id / --upload-file-path / --output-path" >&2
  exit 1
fi
if [[ ! -f "$UPLOAD_FILE" ]]; then
  echo "FATAL: Workload script not found: $UPLOAD_FILE" >&2
  exit 1
fi

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

echo "Detecting system architecture for filenames..."
ARCH_RAW=$(uname -m)
ARCH_NAME=""
if [[ "$ARCH_RAW" == "x86_64" ]]; then
    ARCH_NAME="x86"
elif [[ "$ARCH_RAW" == "aarch64" ]]; then
    ARCH_NAME="arm"
else
    ARCH_NAME="$ARCH_RAW"
fi

OUT_DIR="$(dirname "$(readlink -f "$OUTPUT_PATH")")"
mkdir -p "$OUT_DIR"
SAFE_ID="$(printf '%s' "$ID" | tr -c 'A-Za-z0-9_.-' '_')"

BOP_FILE="$OUT_DIR/bops_${ARCH_NAME}_${SAFE_ID}.txt"
STDOUT_FILE="$OUT_DIR/stdout_${ARCH_NAME}_${SAFE_ID}.log"
STDERR_FILE="$OUT_DIR/stderr_${ARCH_NAME}_${SAFE_ID}.log"
RUNTIME_FILE="$OUT_DIR/runtime_${ARCH_NAME}_${SAFE_ID}.txt"

rm -f "$BOP_FILE" "$STDOUT_FILE" "$STDERR_FILE" "$RUNTIME_FILE"
echo "# started on $(date '+%F %T')" > "$BOP_FILE"

CG="task_${ID}"

echo "Setting up cgroup: $CG..."
sudo mkdir -p /sys/fs/cgroup/perf_event
sudo mount -t cgroup -o perf_event perf_event /sys/fs/cgroup/perf_event 2>/dev/null || true

echo "Creating cgroup with perf_event subsystem..."
sudo cgcreate -g cpu,memory,perf_event:"$CG" >/dev/null 2>&1 || echo "Warning: cgcreate failed (check if perf_event exists)"
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

echo "Configuring perf events for architecture: $ARCH_RAW ($ARCH_NAME)"

declare ORIG_EVENTS
declare FLOPS_EVENTS
declare FINAL_EVENTS

if [[ "$ARCH_RAW" == "x86_64" ]]; then
    echo "Architecture: x86_64 (Intel/AMD). Using x86 perf events."
    ORIG_EVENTS="uops_executed.core,mem_inst_retired.all_stores,mem_inst_retired.all_loads,br_inst_retired.all_branches"
    FLOPS_EVENTS="fp_arith_inst_retired.scalar_double,fp_arith_inst_retired.scalar_single,fp_arith_inst_retired.128b_packed_double,fp_arith_inst_retired.128b_packed_single,fp_arith_inst_retired.256b_packed_double,fp_arith_inst_retired.256b_packed_single,fp_arith_inst_retired.512b_packed_double,fp_arith_inst_retired.512b_packed_single"
    FINAL_EVENTS="${ORIG_EVENTS},${FLOPS_EVENTS}"

elif [[ "$ARCH_RAW" == "aarch64" ]]; then
    echo "Architecture: aarch64 (ARM/Kunpeng). Using ARM core events only."
    ORIG_EVENTS="inst_retired,br_retired,l1d_cache_refill,l1d_cache_wb"
    FLOPS_EVENTS=""
    FINAL_EVENTS="${ORIG_EVENTS}"

else
    echo "FATAL: Unsupported architecture: $ARCH_RAW. Only x86_64 and aarch64 are supported." >&2
    exit 3
fi

build_load_cmd() {
  local p="$1"
  local ext="${p##*.}"
  local first2 firstline interp

  if command -v readlink >/dev/null 2>&1; then
    p="$(readlink -f "$p" 2>/dev/null || echo "$p")"
  fi

  if [[ "$p" == *" "* ]]; then
    echo "FATAL: workload path contains spaces: $p" >&2
    echo "Please move/rename it to a path without spaces." >&2
    return 11
  fi

  first2="$(head -c 2 "$p" 2>/dev/null || true)"
  if [[ "$first2" == "MZ" ]]; then
    echo "FATAL: Detected Windows PE executable (MZ header): $p" >&2
    echo "This environment runs Linux workloads only." >&2
    return 12
  fi

  if head -c 4 "$p" 2>/dev/null | od -An -t u1 2>/dev/null | tr -d ' \n' | grep -q '^127697670$'; then
    echo "$p"
    return 0
  fi

  firstline="$(head -n 1 "$p" 2>/dev/null || true)"
  if [[ "$firstline" == \#!* ]]; then
    if [[ -x "$p" ]]; then
      echo "$p"
      return 0
    fi
    interp="${firstline#\#!}"
    interp="${interp#"${interp%%[![:space:]]*}"}"
    if [[ -n "$interp" ]]; then
      echo "$interp $p"
      return 0
    fi
    echo "FATAL: invalid shebang line in $p" >&2
    return 13
  fi

  if [[ "$ext" == "sh" ]]; then
    echo "bash $p"
    return 0
  elif [[ "$ext" == "py" ]]; then
    echo "python3 $p"
    return 0
  fi

  echo "$p"
}

echo "Starting workload: $UPLOAD_FILE"
LOAD_CMD_STR="$(build_load_cmd "$UPLOAD_FILE")"
LOAD_CMD=($LOAD_CMD_STR)

if [[ "$(basename "$UPLOAD_FILE")" == "mock_load_script.sh" ]]; then
  echo "Detected mock_load_script.sh, injecting ramp args: start=$START_LOAD_PCT end=$END_LOAD_PCT step=$STEP_PCT"
  LOAD_CMD+=("--start-load-pct=$START_LOAD_PCT" "--end-load-pct=$END_LOAD_PCT" "--step-pct=$STEP_PCT")
fi

echo "Starting monitors (perf only)..."
START_TS_NANO=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000") 
INTERVAL_MS="$(to_millis "$COLLECT_FREQUENCY")"

echo "Starting perf with events for $ARCH_NAME..."
echo "Using event list: ${FINAL_EVENTS}"

echo ">>> Phase 1: Launching workload into Cgroup '$CG'..."
sudo cgexec -g cpu,memory,perf_event:"$CG" "${LOAD_CMD[@]}" >"$STDOUT_FILE" 2>"$STDERR_FILE" &
LOAD_PID=$!
echo "Workload started with PID $LOAD_PID. Waiting 0.5s for cgroup population..."

sleep 0.5

PERF_DURATION=$(( $(to_seconds "$MONITOR_DURATION") + 5 ))

echo ">>> Phase 2: Starting Perf Monitor (-a -G mode)..."
perf stat \
  -e "${FINAL_EVENTS}" \
  -a \
  -G "$CG" \
  -I "$INTERVAL_MS" -x , \
  -o "$BOP_FILE" --append \
  -- sleep "$PERF_DURATION" & 

PERF_PID=$!
echo "Perf PID: $PERF_PID, Monitoring Cgroup: $CG"

LOAD_SEC="$(to_seconds "$MONITOR_DURATION")"
RUN_SEC=$((LOAD_SEC + 5))
echo "All processes launched. Load will run for ${LOAD_SEC}s, Monitor will run for ${RUN_SEC}s..."

START_TS=$(date +%s)
WORK_DONE=0
LOAD_ALIVE=1

while :; do
  NOW=$(date +%s)
  ELAPSED=$((NOW-START_TS))
  
  if (( ELAPSED >= LOAD_SEC )) && [[ "$LOAD_ALIVE" -eq 1 ]]; then
    echo ">>> Load duration reached (${LOAD_SEC}s). Stopping perf..."
    kill -INT "$PERF_PID" 2>/dev/null || true
    LOAD_ALIVE=0
  fi

  if (( ELAPSED >= RUN_SEC )); then
    echo ">>> Total monitor buffer time reached (${RUN_SEC}s). Exiting."
    break
  fi

  if [[ "$LOAD_ALIVE" -eq 1 ]]; then
      if ! kill -0 "$LOAD_PID" 2>/dev/null; then
        echo ">>> Workload finished early at ${ELAPSED}s (Process exited)."
        echo ">>> Continuing to monitor idle system until ${RUN_SEC}s..."
        LOAD_ALIVE=0 
      fi
  fi

  sleep 0.2
done
if [[ "$WORK_DONE" -eq 1 ]]; then
  wait "$LOAD_PID" 2>/dev/null || true
fi

echo "Calculating total measured runtime..."
TOTAL_RUNTIME=$(grep -v '^#' "$BOP_FILE" | tail -n 1 | awk -F',' '{print $1}')

if [[ -n "$TOTAL_RUNTIME" ]]; then
    echo "$TOTAL_RUNTIME" > "$RUNTIME_FILE"
    echo "Total measured runtime ($TOTAL_RUNTIME s) saved to $RUNTIME_FILE"
else
    echo "Warning: Could not determine total runtime from $BOP_FILE."
fi

echo "Applying smart data trimming for duration: ${LOAD_SEC}s..."

if [[ -f "$BOP_FILE" ]]; then
    TRIM_THRESHOLD=$(awk -v t="$LOAD_SEC" 'BEGIN {print t + 0.5}')
    
    awk -F, -v limit="$TRIM_THRESHOLD" '
        /^#/ { print; next }
        $1 <= limit { print }
    ' "$BOP_FILE" > "${BOP_FILE}.tmp" && mv "${BOP_FILE}.tmp" "$BOP_FILE"
    
    echo "-> Trimmed Perf data to <= ${TRIM_THRESHOLD}s."
fi

if [[ -f "$BOP_FILE" ]]; then
    REAL_FINAL_TIME=$(grep -v '^#' "$BOP_FILE" | tail -n 1 | awk -F',' '{print $1}')
    if [[ -n "$REAL_FINAL_TIME" ]]; then
        echo "$REAL_FINAL_TIME" > "$RUNTIME_FILE"
        echo "-> Updated runtime file to: $REAL_FINAL_TIME"
    fi
fi

echo "Success! All logs written to $OUT_DIR"
exit 0

```
