#!/bin/bash
# ----------------------------------------------------
# collector.sh: 采集脚本启动器
# ----------------------------------------------------
# 作用：解析后端传来的命令行参数，并启动 Python 执行器。
# ----------------------------------------------------
set -e # 任何命令失败则立即退出

# --- 1. 初始化所有参数的默认值 ---
TASK_ID=""
UPLOAD_FILE_PATH=""
CPU_LIMIT_PCT=100
MEM_LIMIT_PCT=100
MONITOR_DURATION="60s"
COLLECT_FREQUENCY="1s"
START_LOAD_PCT=0
END_LOAD_PCT=0
STEP_PCT=0
OUTPUT_PATH="" # 最终JSON结果的输出路径 (关键!)

# --- 2. 解析传入的命令行参数 (格式: --key="value") ---
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
        *) echo "警告: 未知参数 $1";;
    esac
    shift
done

# --- 3. 检查必要参数 ---
if [ -z "$TASK_ID" ] || [ -z "$UPLOAD_FILE_PATH" ] || [ -z "$OUTPUT_PATH" ]; then
  echo "错误: --id, --upload-file-path, 和 --output-path 是必需的。" >&2
  # 即使失败，也按 API 文档 要求生成一个错误 JSON
  echo "{\"id\": \"$TASK_ID\", \"exit_error\": \"Missing required arguments\"}" > "$OUTPUT_PATH.error"
  exit 1
fi

# --- 4. 调用 Python 执行器 (假设 agent_executor.py 在同一目录) ---
# 我们把所有解析到的变量作为参数传递给Python
# Python 将处理 Cgroups、进程管理和 JSON 生成
echo "启动 agent_executor.py..."
bash ./agent_executor.sh \
    --id="$TASK_ID" \
    --upload-file-path="$UPLOAD_FILE_PATH" \
    --cpu-limit-pct="$CPU_LIMIT_PCT" \
    --mem-limit-pct="$MEM_LIMIT_PCT" \
    --monitor-duration="$MONITOR_DURATION" \
    --collect-frequency="$COLLECT_FREQUENCY" \
    --start-load-pct="$START_LOAD_PCT" \
    --end-load-pct="$END_LOAD_PCT" \
    --step-pct="$STEP_PCT" \
    --output-path="$OUTPUT_PATH"

# --- 5. 捕获 Python 脚本的退出码并返回 ---
exit_code=$?
if [ $exit_code -ne 0 ]; then
    echo "错误: Python 执行器 agent_executor.py 失败，退出码 $exit_code" >&2
    # 如果 Python 失败，它自己会生成错误 JSON，这里只需退出
fi
exit $exit_code