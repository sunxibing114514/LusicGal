#!/usr/bin/env bash
# 通用内存受限运行器（400MB 总 RSS 上限，vcpkg/cmake 长跑用）。
#   mem_watch.sh <cap_mb> <命令...>
# 进程组总 RSS 连续 3 次（10s 间隔）超过 cap 才杀 —— 允许编译器瞬时尖峰。
set -u
CAP_MB="$1"; shift
CAP_KB=$((CAP_MB * 1024))

setsid "$@" &
PID=$!
PGID=$(ps -o pgid= -p $PID | tr -d ' ')

total_rss_kb() {
  local sum=0 pid rss
  for pid in $(pgrep -g "$PGID" 2>/dev/null); do
    rss=$(awk '/^VmRSS:/ {print $2}' "/proc/$pid/status" 2>/dev/null || echo 0)
    sum=$((sum + ${rss:-0}))
  done
  echo "$sum"
}

HITS=0
while kill -0 "$PID" 2>/dev/null; do
  T=$(total_rss_kb)
  if [ "$T" -gt "$CAP_KB" ]; then
    HITS=$((HITS + 1))
    echo "[watchdog] RSS ${T}KB > ${CAP_MB}MB（连续第 $HITS 次）" >&2
    if [ "$HITS" -ge 3 ]; then
      kill -TERM -"$PGID" 2>/dev/null
      sleep 3
      kill -KILL -"$PGID" 2>/dev/null
      echo "MEM_CAP_HIT" >&2
      exit 99
    fi
  else
    HITS=0
  fi
  sleep 10
done

wait "$PID"; RC=$?
echo "cmd_exit=$RC" >&2
exit $RC
