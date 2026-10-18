#!/bin/bash
# Tulis warp-pool.txt (socks5) + warp-pool-http.txt (http): satu URI per baris
# Usage: export-pool.sh [-n 10] [--base-port 40000] [--http-base-port 41000] [--bind 127.0.0.1] [--host HOST] [-o warp-pool.txt]
# --host: host yang ditulis di URI (default: sama dengan --bind; isi IP publik
#         VPS bila bind 0.0.0.0, mis. --host 203.0.113.5).
set -e
N=10; BASE=40000; HTTP_BASE=41000; BIND=127.0.0.1; HOST=""; OUT="warp-pool.txt"
while [ $# -gt 0 ]; do
  case "$1" in
    -n) N="$2"; shift 2;;
    --base-port) BASE="$2"; shift 2;;
    --http-base-port) HTTP_BASE="$2"; shift 2;;
    --bind) BIND="$2"; shift 2;;
    --host) HOST="$2"; shift 2;;
    -o) OUT="$2"; shift 2;;
    *) echo "unknown: $1"; exit 1;;
  esac
done
HOST="${HOST:-$BIND}"
OUT_HTTP="${OUT%.txt}-http.txt"
: > "$OUT"
: > "$OUT_HTTP"
for i in $(seq 1 "$N"); do
  echo "socks5://$HOST:$((BASE + i))" >> "$OUT"
  echo "http://$HOST:$((HTTP_BASE + i))" >> "$OUT_HTTP"
done
echo "wrote $OUT and $OUT_HTTP: $N entries each (host $HOST)"
