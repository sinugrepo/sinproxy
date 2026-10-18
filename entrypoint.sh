#!/bin/bash
# sinproxy/warp-socks entrypoint — PID 1
# Alur: TUN -> dbus -> warp-svc -> register(sekali)/connect -> gost SOCKS5
set -e

log() { echo "[sinproxy] $*"; }

log "setup TUN..."
if [ ! -e /dev/net/tun ]; then
  mkdir -p /dev/net
  mknod /dev/net/tun c 10 200
  chmod 600 /dev/net/tun
fi

log "start dbus..."
mkdir -p /run/dbus
rm -f /run/dbus/pid
dbus-daemon --config-file=/usr/share/dbus-1/system.conf

log "start warp-svc..."
# Redam log daemon (default DEBUG membanjiri stdout -> json.log docker):
# info = cukup (connect/disconnect/error tetap kelihatan).
export WARP_LOG_LEVEL="${WARP_LOG_LEVEL:-info}"
warp-svc --accept-tos &
sleep "${WARP_SLEEP:-5}"

if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
  log "registering new warp identity..."
  warp-cli --accept-tos registration new && log "registered"
  if [ -n "$WARP_LICENSE_KEY" ]; then
    log "license key found, registering..."
    warp-cli --accept-tos registration license "$WARP_LICENSE_KEY" && log "license ok"
  fi
  warp-cli --accept-tos set-mode warp || true
  warp-cli --accept-tos connect
else
  log "already registered, ensuring connected..."
  warp-cli --accept-tos connect || true
fi

log "status: $(warp-cli --accept-tos status 2>&1 || true)"

# Pin IPv6 untuk host yang butuh egress unik per node (mis. opencode.ai rate-limit per IP).
# SOCKS5 remote-resolve memakai DNS container; tanpa pin, happy-eyeballs bisa
# jatuh ke IPv4 anycast shared. /etc/hosts di Docker writable saat runtime.
if [ -n "$V6PIN_HOSTS" ]; then
  for H in $V6PIN_HOSTS; do
    V6S="$(getent hosts "$H" 2>/dev/null | awk '{print $1}' | grep ':' | sort -u || true)"
    if [ -n "$V6S" ]; then
      # /etc/hosts di Docker itu mount khusus: sed -i (rename) gagal "Device busy".
      # Tulis ulang konten via redirect (inode sama, diizinkan).
      grep -v "[[:space:]]$H\$" /etc/hosts > /tmp/hosts.new || true
      cat /tmp/hosts.new > /etc/hosts && rm -f /tmp/hosts.new
      for IP in $V6S; do echo "$IP $H" >> /etc/hosts; done
      log "pinned IPv6 for $H: $(echo $V6S | tr '\n' ' ')"
    else
      log "WARN: no AAAA for $H, skip pin"
    fi
  done
fi

# Blokir egress IPv4 lewat tunnel WARP (mode IPv6-only), tapi biarkan DNS (TCP/UDP 53)
# agar resolusi AAAA tetap jalan. IPv4-only site akan FAIL-FAST (connection refused)
# alih-alih bocor lewat IPv4 anycast shared. Idempoten via comment marker.
apply_v6only() {
  command -v nft >/dev/null 2>&1 || { log "WARN: nft tak ada, V6ONLY dilewati"; return 0; }
  local v4
  v4="$(ip -4 -o addr show dev CloudflareWARP 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
  [ -n "$v4" ] || { log "WARN: tak ada IPv4 di CloudflareWARP, V6ONLY dilewati"; return 0; }
  local n
  n="$(nft list chain inet cloudflare-warp tun 2>/dev/null | grep -c 'sinproxy-v6only' || true)"
  if [ "${n:-0}" -ge 4 ]; then return 0; fi
  log "V6ONLY=1: blokir egress IPv4 via $v4 (DNS 53 dikecualikan)..."
  # Insert tiap rule di position 0 -> urutan akhir: dns-udp, dns-tcp, tcp-reset, generic-reject.
  nft insert rule inet cloudflare-warp tun position 0 ip saddr "$v4" reject comment "sinproxy-v6only" 2>/dev/null || return 0
  nft insert rule inet cloudflare-warp tun position 0 ip saddr "$v4" meta l4proto tcp reject with tcp reset comment "sinproxy-v6only" 2>/dev/null || true
  nft insert rule inet cloudflare-warp tun position 0 ip saddr "$v4" tcp dport 53 accept comment "sinproxy-v6only" 2>/dev/null || true
  nft insert rule inet cloudflare-warp tun position 0 ip saddr "$v4" udp dport 53 accept comment "sinproxy-v6only" 2>/dev/null || true
  log "V6ONLY aktif (IPv4 ditolak, IPv6+DNS lolos)."
}

# Tunggu sampai Connected (maks ~60 dtk) agar log jelas; gost tetap bisa start walau belum connect
for i in $(seq 1 12); do
  ST="$(warp-cli --accept-tos status 2>&1 || true)"
  case "$ST" in
    *Connected*) log "warp connected."; break;;
  esac
  log "waiting for warp connect... ($i/12) status: $ST"
  sleep 5
done

log "start gost socks5 on :${SOCKS_PORT:-1080}..."
if [ "${V6ONLY:-1}" = "1" ]; then
  apply_v6only
  # Watchdog: warp-svc bisa menulis ulang tabel firewall saat reconnect;
  # pastikan aturan V6ONLY selalu ada (diam bila sudah OK).
  ( while sleep 60; do apply_v6only; done ) &
fi
exec gost -L "socks5://:${SOCKS_PORT:-1080}?udp=true"
