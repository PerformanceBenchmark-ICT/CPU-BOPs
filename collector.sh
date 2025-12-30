#!/usr/bin/env bash
# collector.sh (最终参数透传版)
# ----------------------------------------------------
set -euo pipefail

# --- 默认参数 ---
TASK_ID=""
UPLOAD_FILE_PATH=""
CPU_LIMIT_PCT=100
MEM_LIMIT_PCT=100
MONITOR_DURATION="60s"
COLLECT_FREQUENCY="1s"
START_LOAD_PCT=0
END_LOAD_PCT=0
STEP_PCT=0
OUTPUT_PATH=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 参数解析 ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        --id=*) TASK_ID="${1#*=}";;
        --upload-file-path=*) UPLOAD_FILE_PATH="${1#*=}";;
        --cpu-limit-pct=*) CPU_LIMIT_PCT="${1#*=}";;
        --mem-limit-pct=*) MEM_LIMIT_PCT="${1#*=}";;
        --monitor-duration=*) MONITOR_DURATION="${1#*=}";;
        --collect-frequency=*) COLLECT_FREQUENCY="${1#*=}";;
        --start-load-pct=*) START_LOAD_PCT="${1#*=}";;
        --end-load-pct=*) END_LOAD_PCT="${1#*=}";;
        --step-pct=*) STEP_PCT="${1#*=}";;
        --output-path=*) OUTPUT_PATH="${1#*=}";;
    esac
    shift
done

if [ -z "$TASK_ID" ] || [ -z "$UPLOAD_FILE_PATH" ] || [ -z "$OUTPUT_PATH" ]; then
  echo "{\"error\": \"Missing required arguments\"}"
  exit 1
fi

if [ -f "$UPLOAD_FILE_PATH" ]; then
    ABS_UPLOAD_PATH="$(readlink -f "$UPLOAD_FILE_PATH")"
else
    echo "{\"error\": \"Workload file not found\"}"
    exit 1
fi
mkdir -p "$(dirname "$OUTPUT_PATH")"
ABS_OUTPUT_PATH="$(readlink -f "$OUTPUT_PATH")"

AGENT_SCRIPT="${SCRIPT_DIR}/agent_executor.sh"

# --- 1. 启动采集 ---
# 使用 > /dev/null 屏蔽日志，保证只输出最终 JSON
bash "$AGENT_SCRIPT" \
    --id="$TASK_ID" \
    --upload-file-path="$ABS_UPLOAD_PATH" \
    --output-path="$ABS_OUTPUT_PATH" \
    --cpu-limit-pct="$CPU_LIMIT_PCT" \
    --mem-limit-pct="$MEM_LIMIT_PCT" \
    --monitor-duration="$MONITOR_DURATION" \
    --collect-frequency="$COLLECT_FREQUENCY" \
    --start-load-pct="$START_LOAD_PCT" \
    --end-load-pct="$END_LOAD_PCT" \
    --step-pct="$STEP_PCT" > /dev/null 2>&1

# --- 2. 计算结果 ---
ARCH_RAW=$(uname -m)
if [[ "$ARCH_RAW" == "x86_64" ]]; then ARCH_NAME="x86"; else ARCH_NAME="arm"; fi

SAFE_ID=$(printf '%s' "$TASK_ID" | tr -c 'A-Za-z0-9_.-' '_')
OUT_DIR=$(dirname "$ABS_OUTPUT_PATH")
BOP_FILE="${OUT_DIR}/bops_${ARCH_NAME}_${SAFE_ID}.txt"

if [ ! -f "$BOP_FILE" ]; then
    echo "{\"error\": \"Data file not generated\"}"
    exit 1
fi

CALC_SCRIPT="${SCRIPT_DIR}/calc_metrics.py"


python3 "$CALC_SCRIPT" "$BOP_FILE" "$ARCH_NAME" "$COLLECT_FREQUENCY" > "$ABS_OUTPUT_PATH"

if [ $? -eq 0 ]; then
    cat "$ABS_OUTPUT_PATH"
    exit 0
else
    echo "{\"error\": \"Calculation failed\"}"
    exit 1
fi
