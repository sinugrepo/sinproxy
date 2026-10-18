#!/bin/bash
# Probe semua node: warp=on? exit IP? latency?
# Default lewat SOCKS5; pakai --http untuk probe listener HTTP (:8080).
# Usage: healthcheck.sh [-n 10] [--base-port 40000] [--http-base-port 41000] [--bind 127.0.0.1] [--trace] [--http]
set -e
N=10; BASE=40000; HTTP_BASE=41000; BIND=127.0.0.1; TRACE=0; HTTP=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n) N="$2"; shift 2;;
    --base-port) BASE="$2"; shift 2;;
    --http-base-port) HTTP_BASE="$2"; shift 2;;
    --bind) BIND="$2"; shift 2;;
    --trace) TRACE=1; shift;;
    --http) HTTP=1; shift;;
    *) echo "unknown: $1"; exit 1;;
  esac
done

probe() {
  local port="$1"
  if [ "$HTTP" = "1" ]; then
    curl -s --max-time 20 -x "http://$BIND:$port" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null
  else
    curl -s --max-time 20 --socks5-hostname "$BIND:$port" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null
  fi
}

PROTO="socks5"; [ "$HTTP" = "1" ] && PROTO="http"
if [ "$HTTP" = "1" ]; then P_BASE="$HTTP_BASE"; else P_BASE="$BASE"; fi

printf '%-8s %-6s %-8s %-16s %s\n' "NODE" "STATUS" "WARP" "EXIT_IP" "MS"
for i in $(seq 1 "$N"); do
  PORT=$((P_BASE + i))
  START=$(date +%s%3N)
  OUT=$(probe "$PORT" || echo "CURL_FAIL")
  END=$(date +%s%3N); MS=$((END - START))
  if [ "$OUT" = "CURL_FAIL" ]; then
    printf '%-8s %-6s %-8s %-16s %s\n' "warp-n$i" "FAIL" "-" "-" "$MS"
  else
    WARP=$(echo "$OUT" | grep -oP '^warp=\K\w+' || echo "?")
    IP=$(echo "$OUT" | grep -oP '^ip=\K\S+' || echo "?")
    ST="OK"; [ "$WARP" = "on" ] || ST="DEGRADED"
    printf '%-8s %-6s %-8s %-16s %s\n' "warp-n$i" "$ST" "$WARP" "$IP" "$MS"
    echo "$(date -u +%FT%TZ) node=warp-n$i proto=$PROTO port=$PORT status=$ST warp=$WARP ip=$IP ms=$MS" >> health.jsonl
  fi
done
