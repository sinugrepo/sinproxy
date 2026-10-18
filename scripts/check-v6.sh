#!/bin/bash
# check-v6.sh — verifikasi tiap node egress via IPv6 unik (mode V6ONLY).
# - trace dual-stack (www.cloudflare.com)      -> harus IPv6 unik per node, warp=on
# - api64.ipify.org (punya AAAA)               -> harus IPv6 unik per node
# - api.ipify.org (IPv4-ONLY, tanpa AAAA)      -> harus GAGAL cepat (ditolak),
#   BUKAN menampilkan IPv4 shared. Kalau masih tampil 104.x = V6ONLY belum aktif.
# Usage: ./scripts/check-v6.sh [-n 10] [--base-port 40000] [--bind 127.0.0.1]
N=10; BASE=40000; BIND=127.0.0.1
while [ $# -gt 0 ]; do
  case "$1" in
    -n) N="$2"; shift 2;;
    --base-port) BASE="$2"; shift 2;;
    --bind) BIND="$2"; shift 2;;
    *) echo "unknown: $1"; exit 1;;
  esac
done

printf '%-8s %-6s %-38s %-6s %-15s %s\n' "NODE" "STATUS" "EGRESS_V6(trace)" "WARP" "IPIFY64" "V4BLOCK"
declare -A SEEN
for i in $(seq 1 "$N"); do
  PORT=$((BASE + i))
  TRACE=$(curl -s --max-time 20 --socks5-hostname "$BIND:$PORT" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || echo CURL_FAIL)
  if [ "$TRACE" = "CURL_FAIL" ] || [ -z "$TRACE" ]; then
    printf '%-8s %-6s %-38s %-6s %-15s %s\n' "warp-n$i" "FAIL" "-" "-" "-" "-"
    continue
  fi
  WARP=$(echo "$TRACE" | grep -oP '^warp=\K\w+' || echo "?")
  TIP=$(echo "$TRACE" | grep -oP '^ip=\K\S+' || echo "?")
  IP64=$(curl -s --max-time 20 --socks5-hostname "$BIND:$PORT" https://api64.ipify.org 2>/dev/null || echo "?")
  # IPv4-only domain: harap GAGAL (exit != 0). Sukses + IP = kebocoran IPv4.
  V4OUT=$(curl -s --max-time 20 --socks5-hostname "$BIND:$PORT" https://api.ipify.org 2>/dev/null); V4RC=$?
  if [ $V4RC -ne 0 ] || [ -z "$V4OUT" ]; then V4="BLOCKED"; else V4="LEAK:$V4OUT"; fi
  ST="OK"; [ "$WARP" = "on" ] || ST="DEGRADED"
  case "$TIP" in *:* ) ;; * ) ST="V4-FB";; esac   # trace harus IPv6 (mengandung ':')
  [ "$V4" = "BLOCKED" ] || ST="V4-LEAK"
  if [ -n "${SEEN[$TIP]:-}" ]; then ST="$ST+DUP"; else SEEN[$TIP]=1; fi
  printf '%-8s %-6s %-38s %-6s %-15s %s\n' "warp-n$i" "$ST" "$TIP" "$WARP" "$IP64" "$V4"
done
echo "---"
echo "OK = IPv6 unik + warp=on + IPv4-only diblokir. V4-LEAK = V6ONLY belum aktif di node itu."
echo "Catatan: api.ipify.org memang IPv4-only (tanpa AAAA) -> selalu BLOCKED saat V6ONLY=1. Itu benar."
