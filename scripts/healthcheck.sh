#!/bin/bash
# Probe semua SOCKS node: warp=on? exit IP? latency?
# Usage: healthcheck.sh [-n 10] [--base-port 40000] [--bind 127.0.0.1] [--trace]
set -e
N=10; BASE=40000; BIND=127.0.0.1; TRACE=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n) N="$2"; shift 2;;
    --base-port) BASE="$2"; shift 2;;
    --bind) BIND="$2"; shift 2;;
    --trace) TRACE=1; shift;;
    *) echo "unknown: $1"; exit 1;;
  esac
done

printf '%-8s %-6s %-8s %-16s %s\n' "NODE" "STATUS" "WARP" "EXIT_IP" "MS"
for i in $(seq 1 "$N"); do
  PORT=$((BASE + i))
  START=$(date +%s%3N)
  OUT=$(curl -s --max-time 20 --socks5-hostname "$BIND:$PORT" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || echo "CURL_FAIL")
  END=$(date +%s%3N); MS=$((END - START))
  if [ "$OUT" = "CURL_FAIL" ]; then
    printf '%-8s %-6s %-8s %-16s %s\n' "warp-n$i" "FAIL" "-" "-" "$MS"
  else
    WARP=$(echo "$OUT" | grep -oP '^warp=\K\w+' || echo "?")
    IP=$(echo "$OUT" | grep -oP '^ip=\K\S+' || echo "?")
    ST="OK"; [ "$WARP" = "on" ] || ST="DEGRADED"
    printf '%-8s %-6s %-8s %-16s %s\n' "warp-n$i" "$ST" "$WARP" "$IP" "$MS"
    echo "$(date -u +%FT%TZ) node=warp-n$i port=$PORT status=$ST warp=$WARP ip=$IP ms=$MS" >> health.jsonl
  fi
done
