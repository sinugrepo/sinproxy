# SinProxy — N WARP-CLI dalam Docker, dibungkus SOCKS5 + HTTP

Satu image (`sinproxy/warp-socks`), N container, tiap container = 1 identitas
WARP = 1 exit IP (best-effort, anycast) dengan 2 endpoint: SOCKS5 dan HTTP.

```text
socks5://127.0.0.1:40001        http://127.0.0.1:41001
socks5://127.0.0.1:40002        http://127.0.0.1:41002
...                             ...
socks5://127.0.0.1:40010        http://127.0.0.1:41010
```

Port HTTP = `HTTP_BASE_PORT + i` (default `BASE_PORT + 1000`), listener HTTP
internal container di `:8080`.

Detail desain: lihat `PRD.md`.

## Prasyarat host

- Linux x86_64/arm64, Docker + compose plugin, `/dev/net/tun`, NET_ADMIN
- Outbound UDP ke Cloudflare tidak diblokir (WireGuard/MASQUE)

## Cara pakai

```bash
cp .env.example .env        # opsional, default sudah N=10
./mw run                    # generate compose -> up -> healthcheck (socks+http) -> pool files
./mw status                 # ps + probe semua port SOCKS5
./mw status --http          # ps + probe lewat HTTP proxy
./mw stop                   # down (data identitas dipertahankan)
./mw restart                 # down + up (identitas tetap, tanpa registrasi ulang)
./mw recreate warp-n4       # recreate 1 node buruk saja
./mw wipe-all               # hapus SEMUA identitas (registrasi ulang total, konfirmasi YES)
```

Skala lain: `COUNT=7 ./mw run` atau `./mw run -n 7`.

## Verifikasi manual

```bash
./scripts/check-v6.sh   # 10 node: IPv6 unik + warp=on + IPv4-only diblokir
curl -s --max-time 20 --socks5-hostname 127.0.0.1:40003 \
  https://www.cloudflare.com/cdn-cgi/trace | grep -E '^(warp|ip)='
curl -s --max-time 20 -x http://127.0.0.1:41003 \
  https://www.cloudflare.com/cdn-cgi/trace | grep -E '^(warp|ip)='
curl -s --max-time 20 --socks5-hostname 127.0.0.1:40003 https://api64.ipify.org; echo
./scripts/healthcheck.sh -n 10 --http      # tabel probe via HTTP proxy
docker exec warp-n3 warp-cli --accept-tos status
```

> JANGAN cek pakai `https://api.ipify.org` — domain itu IPv4-only (tanpa
> AAAA) sehingga pasti keluar via IPv4 anycast shared Cloudflare
> (`104.28.x.x`, sama di semua node). Itu bawaan WARP gratis, bukan bug.
> Pakai `api64.ipify.org` atau endpoint dual-stack untuk melihat IPv6 unik.

## File penting

| File | Fungsi |
|------|--------|
| `Dockerfile` | image: ubuntu 24.04 + warp-cli resmi + gost v3 (multi-arch amd64/arm64) |
| `entrypoint.sh` | TUN -> dbus -> warp-svc -> register(sekali)/connect -> gost :1080 (SOCKS5) + :8080 (HTTP) |
| `scripts/generate-compose.py` | generate N service, port SOCKS5 + HTTP berurutan |
| `scripts/healthcheck.sh` | probe warp=on + exit IP + ms per port (SOCKS5, atau HTTP via `--http`) |
| `scripts/check-v6.sh` | verifikasi IPv6-only: trace v6 unik + api64 + pastikan api.ipify (v4-only) diblokir |
| `scripts/export-pool.sh` | tulis warp-pool.txt (socks5) + warp-pool-http.txt (http) |
| `mw` | operator satu perintah |
| `warp-pool.txt` | daftar proxy SOCKS5 siap pakai (di-generate, jangan commit) |
| `warp-pool-http.txt` | daftar proxy HTTP siap pakai (di-generate, jangan commit) |
| `data-n*/` | identitas WARP per node (jangan commit, jangan hapus sembarangan) |

## Catatan operasional

- Bind default `127.0.0.1` — jangan buka ke publik tanpa auth + firewall.
  (Deploy VPS: `BIND_ADDR=0.0.0.0` di `.env`; SOCKS5 & HTTP masih tanpa auth.)
- Port SOCKS5 = `BASE_PORT+i`, port HTTP = `HTTP_BASE_PORT+i` (default
  `BASE_PORT+1000` → 41001–41010). Salah satu host port bentrok ⇒ container
  gagal start; cek `ss -lnt` di VPS.
- Isi `PUBLIC_HOST=<ip-publik-vps>` di `.env` bila bind `0.0.0.0`, supaya
  `warp-pool.txt`/`warp-pool-http.txt` berisi IP VPS, bukan `0.0.0.0`.
- File `data-n*` root-owned: wipe selalu via `./mw recreate`, jangan `rm` manual.
- Exit IP bisa duplikat antar node (anycast Cloudflare) — normal. IPv6 trace unik
  per node, IPv4 egress sering berbagi anycast yang sama.
- IPv4 egress pool yang terlihat: `104.28.221.97`, `104.28.253.99`, `104.28.221.99`.
- **V6ONLY (2026-10-10, default `V6ONLY=1`): tiap container menolak egress IPv4
  lewat tunnel (nft, DNS port 53 dikecualikan, ada watchdog 60 dtk). Hasil:
  domain dual-stack selalu keluar via IPv6 unik per node; domain IPv4-only
  (mis. `api.ipify.org`) langsung `connection refused` — fail-fast, bukan
  diam-diam bocor ke IPv4 shared. Matikan bila butuh IPv4:
  `V6ONLY=0` di `.env`, lalu rebuild (`docker compose up -d --build`).
  IPv4 WARP gratis TIDAK bisa dibuat variatif — keterbatasan provider.
- **V6PIN (2026-10-04): tiap container pin IPv6 `opencode.ai` di /etc/hosts
  (env `V6PIN_HOSTS`, default `opencode.ai`). Tanpa ini happy-eyeballs bisa jatuh
  ke IPv4 anycast shared; dengan pin, 50/50 request = 10 IPv6 unik stabil.
  Verifikasi: `python3 scripts/v6pool.py check -r 5`. Tambah host lain:
  `V6PIN_HOSTS="opencode.ai api.contoh.com"` di `.env`, lalu `./mw restart`.
- RAM ±80 MB/node. Restart container tidak registrasi ulang (terverifikasi).
