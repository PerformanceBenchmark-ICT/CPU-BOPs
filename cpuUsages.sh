#!/bin/bash
# ----------------------------------------------------
# cpuUsages.sh: 持续监测 CPU 利用率 (V3 - 修复 awk 格式)
# ----------------------------------------------------
# 作用：每秒钟获取一次全系统 CPU 利用率，
#      并按 "YYYY-MM-DD HH:MM:SS CPU Usage: XX.X%" 的格式 输出
# ----------------------------------------------------


LC_ALL=C stdbuf -oL sar -u 1 | awk 'NR>3 && $NF ~ /[0-9.]+/ { 
    printf "%s %s CPU Usage: %.1f%%\n", \
    strftime("%Y-%m-%d"), strftime("%H:%M:%S"), \
    100 - $NF 
    fflush() # 确保 awk 自己也立即刷新
}'