#!/bin/bash
set -e

cleanup() {
  echo "[DEBUG] trap triggered! $$ $(date '+%H:%M:%S')" >> /tmp/mock_cleanup.log
  echo "[DEBUG] PGID=$(ps -o pgid= $$ | tr -d ' ')" >> /tmp/mock_cleanup.log
  pkill -9 -P $$ 2>/dev/null || true
}
trap cleanup INT TERM EXIT

# --------------------------------



# ----------------------------------------------------
# mock_load_script.sh (模拟后端上传的脚本)
# ----------------------------------------------------
# (第 1 部分：解析参数 - 保持不变)
# ...
while [ "$#" -gt 0 ]; do
    case "$1" in
        --start-load-pct=*) START_PCT="${1#*=}";;
        --end-load-pct=*) END_PCT="${1#*=}";;
        --step-pct=*) STEP_PCT="${1#*=}";;
        *) ;;
    esac
    shift
done

# (第 2 部分：计算核心数 - 保持不变)
# ...
TOTAL_CORES=$(nproc)
START_CORES=$(( (TOTAL_CORES * START_PCT) / 100 ))
END_CORES=$(( (TOTAL_CORES * END_PCT) / 100 ))
STEP_CORES=$(( (TOTAL_CORES * STEP_PCT) / 100 ))

if [ "$STEP_CORES" -eq 0 ] && [ "$STEP_PCT" -gt 0 ]; then
    STEP_CORES=1
fi
if [ "$START_CORES" -eq 0 ] && [ "$START_PCT" -gt 0 ]; then
    START_CORES=1
fi

STEP_DURATION_SECONDS=10 

echo "模拟负载脚本：总核心 $TOTAL_CORES."
echo "模拟负载脚本：策略: $START_CORES -> $END_CORES (步长 $STEP_CORES), 每 $STEP_DURATION_SECONDS 秒一步"

CURRENT_CORES=0


# 1. 立即启动 START_CORES 个进程 (核心 0 到 START_CORES-1)
echo "模拟负载脚本：立即启动 $START_CORES 个核心 (初始负载)..."
for ((i = 0; i < START_CORES; i++)); do
    if [ $i -ge $TOTAL_CORES ]; then break; fi # 防止超出总核心数
    echo "模拟负载脚本：在核心 $i 上启动 CPU 负载..."
    # ✅ 确保命令是 'bash -c ...'
    taskset -c $i awk 'BEGIN{srand(); while(1){x=sin(rand())*cos(rand())}}' &
done

CURRENT_CORES=$START_CORES

# 2. 爬坡：从 START_CORES 增加到 END_CORES
# (仅当步长大于0且目标大于起点时执行)
if [ $STEP_CORES -gt 0 ] && [ $END_CORES -gt $START_CORES ]; then
    
    # 我们从 CURRENT_CORES (即 START_CORES) 开始循环，直到 END_CORES
    for ((c = CURRENT_CORES; c < END_CORES; c += STEP_CORES)); do
        
        echo "模拟负载脚本：当前负载 $CURRENT_CORES 核心。等待 $STEP_DURATION_SECONDS 秒..."
        sleep $STEP_DURATION_SECONDS
        
        # 计算这一步要启动到的核心上限
        NEXT_LIMIT=$((c + STEP_CORES))
        if [ $NEXT_LIMIT -gt $END_CORES ]; then
            NEXT_LIMIT=$END_CORES
        fi
        
        echo "模拟负载脚本：爬坡... 启动核心 $CURRENT_CORES 到 $NEXT_LIMIT..."
        for ((i = CURRENT_CORES; i < NEXT_LIMIT; i++)); do
            if [ $i -ge $TOTAL_CORES ]; then break; fi # 防止超出总核心数
            echo "模拟负载脚本：在核心 $i 上启动 CPU 负载..."
             # ✅ 确保命令是 'bash -c ...'
            taskset -c $i awk 'BEGIN{srand(); while(1){x=sin(rand())*cos(rand())}}' &
        done
        
        CURRENT_CORES=$NEXT_LIMIT
    done

elif [ $END_CORES -gt $START_CORES ]; then
    # 如果步长为 0，但 END > START，则立即补足剩余核心
    echo "模拟负载脚本：步长为0，立即启动剩余核心至 $END_CORES..."
    for ((i = CURRENT_CORES; i < END_CORES; i++)); do
        if [ $i -ge $TOTAL_CORES ]; then break; fi
         # ✅ 确保命令是 'bash -c ...'
        taskset -c $i awk 'BEGIN{srand(); while(1){x=sin(rand())*cos(rand())}}' &
    done
    CURRENT_CORES=$END_CORES
fi

echo "模拟负载脚本：所有负载已启动 (共 $CURRENT_CORES 个)。等待被 collector.sh 终止..."
# 保持脚本运行，直到被 agent_executor.py 杀死
wait