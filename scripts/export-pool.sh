#!/bin/bash
# Tulis warp-pool.txt: satu socks5 URI per baris
# Usage: export-pool.sh [-n 10] [--base-port 40000] [--bind 127.0.0.1] [-o warp-pool.txt]
set -e
N=10; BASE=40000; BIND=127.0.0.1; OUT="warp-pool.txt"
while [ $# -gt 0 ]; do
  case "$1" in
    -n) N="$2"; shift 2;;
    --base-port) BASE="$2"; shift 2;;
    --bind) BIND="$2"; shift 2;;
    -o) OUT="$2"; shift 2;;
    *) echo "unknown: $1"; exit 1;;
  esac
done
: > "$OUT"
for i in $(seq 1 "$N"); do
  echo "socks5://$BIND:$((BASE + i))" >> "$OUT"
done
echo "wrote $OUT: $N entries"
