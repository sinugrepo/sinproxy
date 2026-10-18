# PRD — SinProxy: WARP-CLI dalam Docker dibungkus SOCKS5 Proxy (N Container)

- Status: MVP SELESAI 2026-10-04 — 10/10 node warp=on, healthy, restart tanpa registrasi ulang
- Host: arm64, 24 GB RAM (bukan VPS 2 GB di catatan lama — host ini lain mesin)
- Tanggal: 2026-10-04
- Lokasi repo: `/home/sinug/apps/sinproxy`
- Target awal: 10 container = 10 proxy SOCKS5, masing-masing berisi 1 WARP-CLI independen
- Referensi terbukti: `caomingjun/warp` (warp-cli + GOST, 968 stars), pola multi-exit `Micolaabdi/multi-warp` (N volume = N identitas)

---

## 1. Ringkasan eksekutif

Bangun satu Docker image `sinproxy/warp-socks` yang menjalankan Cloudflare WARP-CLI resmi di dalam container dan mengeksposnya sebagai proxy SOCKS5. Satu container = satu identitas WARP = satu exit IP (best-effort, karena anycast Cloudflare bisa reuse IP). Jalankan 10 replika via docker-compose dengan port host berurutan (`40001–40010`) dan volume data terpisah (`data-n1…data-n10`), sehingga didapat 10 endpoint SOCKS5 siap pakai:

```text
socks5://127.0.0.1:40001
socks5://127.0.0.1:40002
...
socks5://127.0.0.1:40010
```

## 2. Latar belakang & masalah

- Kebutuhan multi-egress: testing, isolasi trafik, rotasi IP, geo-check — semua lewat jaringan Cloudflare WARP.
- WARP-CLI tidak bisa jalan bare-metal berdampingan 10 identitas dalam satu OS tanpa konflik TUN/daemon/registrasi.
- Solusi: isolasi per-identitas di level container (own netns, own TUN, own `/var/lib/cloudflare-warp`, own `warp-svc`).
- Pola ini sudah terbukti di `warp-docker` (single) dan `multi-warp` (N-exit pool dengan recreate-loop sampai IP unik).

## 3. Tujuan (Goals)

1. Satu `Dockerfile` + `entrypoint.sh` yang reproducible: build sekali, jalan di x86_64 dan arm64.
2. `docker-compose.yml` (digenerate) untuk N=10 dengan port, volume, dan nama container deterministik.
3. Setiap node lolos verifikasi: `warp=on` via `cdn-cgi/trace` melalui SOCKS-nya sendiri + exit IP tercatat.
4. Operasional one-command: `run / stop / status / export-pool / recreate-bad-node`.
5. Persistensi identitas: restart container tidak registrasi ulang (selama volume `data-nX` tidak dihapus).

### Non-tujuan (awal)

- Bukan layanan VPN publik / jualan proxy. Bind default localhost saja.
- Bukan garansi 10 IP publik unik 100% — anycast Cloudflare bisa memberikan IP sama ke 2+ node. PRD ini menuntut best-effort + deteksi duplikat + recreate otomatis (batas ronde).
- Bukan HTTP forward proxy di MVP (opsional fase 2 via GOST `-L http://:8080`).

## 4. Persona & use case

- Dev/QA: `curl --socks5-hostname 127.0.0.1:40003 https://api.ipify.org` untuk cek exit IP per node.
- Scraper/tester: ambil `warp-pool.txt`, round-robin 10 proxy.
- Operator: `./mw status` lihat mana node FAIL / `warp=off` / IP duplikat, recreate satuan tanpa ganggu 9 lainnya.

User stories:
1. Sebagai operator, saya `COUNT=10 ./mw run` dan 5 menit kemudian dapat 10 SOCKS5 hidup.
2. Sebagai client, saya baca `warp-pool.txt` dan langsung pakai tanpa tahu detail WARP.
3. Sebagai operator, saya `docker compose restart warp-n4` dan node itu kembali `warp=on` tanpa registrasi ulang.

## 5. Ruang lingkup

### MVP (wajib)

- FR-01: Image berisi `warp-cli` + `warp-svc` resmi (apt `pkg.cloudflareclient.com`), `dbus`, `curl`, `nftables`, GOST.
- FR-02: Entrypoint otomatis: TUN → dbus → warp-svc → tunggu → register (sekali) → connect → start SOCKS di `:1080`.
- FR-03: Compose 10 service (`warp-n1…n10`), port host `40001–40010 → 1080`, volume `./data-nX:/var/lib/cloudflare-warp`.
- FR-04: Healthcheck per node (dari host, lewat SOCKS): `trace warp=on` + catat exit IP.
- FR-05: `warp-pool.txt` ter-generate (satu URI per baris).
- FR-06: Recreate node buruk satuan (wipe volume + `up -d` ulang service itu saja).
- FR-07: Persistensi: `restart: unless-stopped`, identitas survive reboot host.

### Fase 2 (opsional, tidak di MVP)

- SOCKS auth user/pass per node.
- HTTP proxy pendamping (`:8080`) via GOST.
- WARP+ license key / Zero Trust enrollment per node.
- Prometheus exporter (socks latency, warp status per node).
- Rotasi otomatis per interval.

## 6. Persyaratan fungsional detail

| ID | Kebutuhan | Kriteria terima |
|----|-----------|-----------------|
| FR-01 | Build image | `docker build -t sinproxy/warp-socks .` sukses di amd64; (arm64 best-effort) |
| FR-02 | Registrasi sekali | Boot pertama buat `data-nX/reg.json`; boot kedua log `already registered, skip` |
| FR-03 | Koneksi | `warp-cli status` di tiap container = `Connected` dalam ≤120 dtk boot pertama |
| FR-04 | SOCKS listen | `ss -lnt` di container ada `:1080`; dari host `curl --socks5-hostname 127.0.0.1:4000N https://www.cloudflare.com/cdn-cgi/trace` berisi `warp=on` |
| FR-05 | Isolasi identitas | `data-n1…n10` direktori terpisah; tidak ada share volume antar node |
| FR-06 | Port deterministik | node `n` → host port `BASE_PORT+n` (default BASE=40000 → 40001…40010), bind `127.0.0.1` |
| FR-07 | Healthcheck | script lapor per port: OK/FAIL + `warp=` + exit IP + ms |
| FR-08 | Pool file | `warp-pool.txt` 10 baris valid, urut |
| FR-09 | Recreate satuan | `RECREATE=warp-n4 ./mw recreate` hanya sentuh node itu; 9 lain uptime jalan terus |
| FR-10 | Log readable | `docker compose logs warp-nX` tampilkan tahap entrypoint (tun ok, dbus ok, registered/connected, gost listening) |

## 7. Persyaratan non-fungsional

- NFR-01 Startup: boot dingin 10 node ≤5 menit sampai semua `warp=on` (registrasi pertama bisa lebih lama).
- NFR-02 Resource: 1 node ≈ 50–100 MB RAM + 1 warp-svc + 1 gost. **10 node ≈ 0.5–1 GB RAM. PENTING: VPS saat ini (~360 MB free dari 2 GB) TIDAK cukup untuk 10 node sekaligus — MVP di VPS ini uji 2–3 node dulu, atau tambah RAM/pindah host untuk 10.**
- NFR-03 Disk: image ~400–600 MB; 10 volume data kecil (masing-masing <50 MB).
- NFR-04 Jaringan host: butuh `/dev/net/tun`, capability `NET_ADMIN`, outbound UDP (WireGuard ke Cloudflare) tidak diblokir, `net.ipv4.conf.all.src_valid_mark=1`, IPv6 tidak di-disable total.
- NFR-05 Restart: `unless-stopped`; host reboot → semua node kembali tanpa intervensi.
- NFR-06 Keamanan default: bind `127.0.0.1` saja; SOCKS tanpa auth hanya boleh di loopback. Bind `0.0.0.0`/LAN wajib auth + firewall allowlist.
- NFR-07 Observability: setiap probe catat timestamp, exit IP, `warp=` flag ke `health.jsonl`.

## 8. Arsitektur teknis

```text
HOST (Ubuntu, docker, /dev/net/tun)
│
├─ warp-n1  [netns sendiri]  warp-svc + warp-cli (reg data-n1) + GOST :1080 ──► Cloudflare edge (exit IP A)
│   └── publish 127.0.0.1:40001 → :1080
├─ warp-n2  ... data-n2 ──► edge (exit IP B)   → 127.0.0.1:40002
│ ...
└─ warp-n10 ... data-n10 ──► edge (exit IP J)  → 127.0.0.1:40010

CLIENT (curl / app / scraper)
   └── baca warp-pool.txt, pakai socks5://127.0.0.1:4000N per request (round-robin manual)
```

Isi container (satu proses utama `entrypoint.sh` membungkus 2 daemon):

1. `dbus-daemon` (wajib — `warp-svc` butuh D-Bus sistem).
2. `warp-svc --accept-tos &` (daemon resmi, bikin interface `CloudflareWARP`).
3. `warp-cli` (CLI kontrol: register/connect/mode/status).
4. `gost -L socks5://:1080` (SOCKS5 server; trafiknya otomatis keluar lewat interface WARP karena mode `warp` me-route semua trafik container).
5. `entrypoint.sh` sebagai PID 1: orkestrasi + `exec`/wait agar crash gost menghentikan container (restart policy yang hidupkan lagi).

Keputusan mode WARP-CLI (dipilih di MVP):

- **Pilih: `warp-cli set-mode warp` + GOST di `:1080`** (pola `warp-docker`, paling teruji; mendukung TCP+UDP ASSOCIATE; gampang tambah HTTP proxy nanti).
- Alternatif ditolak untuk MVP: native `set-mode proxy` (`:40000` built-in) — lebih ringan tanpa GOST tapi perilaku versi-ke-versi kurang konsisten dan dokumentasinya tipis. Boleh jadi eksperimen fase 2.

## 9. Spesifikasi Dockerfile & entrypoint

### 9.1 Dockerfile (acuan, sesuaikan saat implementasi)

```dockerfile
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive WARP_SLEEP=5
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg lsb-release dbus iputils-ping iproute2 nftables \
 && curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflare-client.list \
 && apt-get update && apt-get install -y cloudflare-warp \
 && rm -rf /var/lib/apt/lists/*
# GOST (ganti versi saat build — cek rilis go-gost/gost v3)
ARG GOST_VER=3.1.0
RUN curl -fsSL -o /tmp/gost.tgz \
      https://github.com/go-gost/gost/releases/download/v${GOST_VER}/gost_${GOST_VER}_linux_amd64.tar.gz \
 && tar -xzf /tmp/gost.tgz -C /usr/local/bin gost && chmod +x /usr/local/bin/gost && rm /tmp/gost.tgz
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 1080
HEALTHCHECK --interval=60s --timeout=15s --start-period=90s --retries=3 \
  CMD curl -s --max-time 10 https://www.cloudflare.com/cdn-cgi/trace | grep -q warp=on || exit 1
ENTRYPOINT ["/entrypoint.sh"]
```

### 9.2 entrypoint.sh (alurnya — bukan skrip final)

```bash
#!/bin/bash
set -e
echo "[sinproxy] setup TUN..."
[ -e /dev/net/tun ] || { mkdir -p /dev/net; mknod /dev/net/tun c 10 200; chmod 600 /dev/net/tun; }
echo "[sinproxy] start dbus..."
mkdir -p /run/dbus; rm -f /run/dbus/pid
dbus-daemon --config-file=/usr/share/dbus-1/system.conf
echo "[sinproxy] start warp-svc..."
warp-svc --accept-tos &
sleep "${WARP_SLEEP:-5}"
if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
  echo "[sinproxy] registering..."
  warp-cli --accept-tos registration new && echo "[sinproxy] registered"
  if [ -n "$WARP_LICENSE_KEY" ]; then
    warp-cli --accept-tos registration license "$WARP_LICENSE_KEY" && echo "[sinproxy] license ok"
  fi
  warp-cli --accept-tos set-mode warp || true
  warp-cli --accept-tos connect
else
  echo "[sinproxy] already registered, ensuring connected..."
  warp-cli --accept-tos connect || true
fi
echo "[sinproxy] status: $(warp-cli --accept-tos status || true)"
echo "[sinproxy] start gost socks5 :1080..."
exec gost -L "socks5://:${SOCKS_PORT:-1080}?udp=true"
```

Env yang didukung: `WARP_SLEEP` (default 5), `WARP_LICENSE_KEY` (opsional WARP+), `SOCKS_PORT` (default 1080), `SOCKS_USER`/`SOCKS_PASS` (fase 2).

## 10. Spesifikasi docker-compose (N=10)

Jangan tulis 10 service manual — generate. Pola per service (contoh n=1):

```yaml
services:
  warp-n1:
    build: .
    image: sinproxy/warp-socks:1.0
    container_name: warp-n1
    restart: unless-stopped
    device_cgroup_rules:
      - 'c 10:200 rwm'
    cap_add: [NET_ADMIN, MKNOD, AUDIT_WRITE]
    sysctls:
      net.ipv6.conf.all.disable_ipv6: 0
      net.ipv4.conf.all.src_valid_mark: 1
    ports:
      - "127.0.0.1:40001:1080"
    environment:
      - WARP_SLEEP=5
      # - WARP_LICENSE_KEY=${WARP_LICENSE_KEY:-}
    volumes:
      - ./data-n1:/var/lib/cloudflare-warp
```

Aturan generate (`scripts/generate-compose.py -n 10 --base-port 40000 --bind 127.0.0.1`):

- service `warp-n{i}`, container_name sama, port `{bind}:{base+i}:1080`, volume `./data-n{i}:/var/lib/cloudflare-warp`.
- `.env`: `COUNT=10`, `BASE_PORT=40000`, `BIND=127.0.0.1`, `WARP_LICENSE_KEY=` (kosong = WARP gratis).
- `.gitignore`: `data-n*/`, `warp-pool.txt`, `health.jsonl`, `.env` (bila berisi license).

## 11. Struktur repo yang diusulkan

```text
sinproxy/
├── PRD.md                  (file ini)
├── Dockerfile
├── entrypoint.sh
├── .env.example            (COUNT, BASE_PORT, BIND, WARP_LICENSE_KEY)
├── scripts/
│   ├── generate-compose.py (generate docker-compose.yml utk -n N)
│   ├── healthcheck.sh      (probe semua port: warp=on + exit IP + ms → tabel + health.jsonl)
│   └── export-pool.sh      (tulis warp-pool.txt)
├── mw                      (one-command: run/stop/status/restart/recreate <node>)
├── docker-compose.yml      (hasil generate, N=10)
├── warp-pool.txt           (hasil generate, 10 baris)
└── README.md               (cara pakai singkat)
```

## 12. Operasional (kontrak CLI `mw`)

- `./mw run [-n 10]` = generate-compose (bila N/bind berubah) → `mkdir data-nX` → `pull/build + up -d` → tunggu awal 60–90 dtk → healthcheck → recreate node buruk (FAIL / `warp≠on` / IP duplikat, serial batch 1–2, jeda ≥30 dtk) maks `MAX_ROUNDS=3` → export-pool.
- `./mw status` = `docker compose ps` + probe cepat per port.
- `./mw stop` = `docker compose down` (data dipertahankan).
- `./mw recreate warp-n4` = `stop+rm service itu` → wipe volume via helper container root (`docker run --rm -v $PWD/data-n4:/wipe --user 0:0 alpine sh -c 'rm -rf /wipe/*'` — karena file reg root-owned) → `up -d` service itu → tunggu → probe ulang.
- `./mw wipe-all` = down + hapus semua `data-n*` (registrasi ulang total, butuh konfirmasi).

Perintah verifikasi manual per node (contoh n=3):

```bash
curl -s --max-time 20 --socks5-hostname 127.0.0.1:40003 https://www.cloudflare.com/cdn-cgi/trace | grep -E 'warp=|ip='
curl -s --max-time 20 --socks5-hostname 127.0.0.1:40003 https://api.ipify.org; echo
docker exec warp-n3 warp-cli status
docker exec warp-n3 warp-cli registration show
```

## 13. Keamanan

- S-01 Default bind `127.0.0.1`. Dilarang `0.0.0.0` tanpa auth + firewall.
- S-02 Jika suatu saat bind LAN/publik: wajib SOCKS auth (fase 2) + firewall allowlist IP farm/Tailscale saja untuk `40001–40010`. SOCKS terbuka = open proxy = penyalahgunaan atas nama kita.
- S-03 Jangan commit `data-n*/` (device key + identitas WARP) dan `.env` berisi license.
- S-04 Berlaku ToS Cloudflare WARP untuk tiap identitas. Proyek ini lem infra, bukan alat bypass ToS.
- S-05 License WARP+ (bila dipakai) via env, tidak di-hardcode di image.

## 14. Observability & acceptance test (definisi lolos)

 healthcheck.sh per port mencatat: `port, ok(fail/ok), warp(on/off), exit_ip, ms`. Lolos MVP bila:

1. `docker compose ps` 10/10 `running`.
2. Probe host 10/10 `warp=on`.
3. `warp-pool.txt` 10 baris, tiap baris lolos `curl --socks5-hostname` dalam ≤20 dtk.
4. Restart 1 node (`restart warp-n5`) kembali OK tanpa hapus volume.
5. Host reboot (simulasi `compose down && up -d`) semua kembali tanpa registrasi ulang.
6. Unik IP: target 10 unik; toleransi: ≥8 unik lolos dengan catatan (anycast). Di bawah itu → jalankan recreate-loop, bila tetap gagal catat sebagai keterbatasan provider, bukan bug image.

## 15. Risiko & mitigasi

| Risiko | Dampak | Mitigasi |
|--------|--------|----------|
| RAM VPS 2 GB (free ~360 MB) vs kebutuhan ~1 GB utk 10 node | OOM, daemon hang, `warp=off` massal | Uji MVP 2–3 node di VPS ini; 10 node di host ≥4 GB atau bagi 2 host @5 node |
| Registrasi serentak 10 node dari 1 IP → rate-limit/hang | banyak node stuck `warp=off` | recreate serial (batch 1–2, jeda 30–60 dtk), `WARP_SLEEP=5–10`, `MAX_ROUNDS` batasi |
| Exit IP duplikat (anycast) | unik <10 | deteksi + recreate node duplikat; terima 8–10 unik sebagai normal |
| `/dev/net/tun` hilang / NET_ADMIN ditolak (shared hosting, rootless, Docker Desktop Windows) | container gagal start | prasyarat host: `modprobe tun`, Docker rootfull Linux; dokumentasikan, gagalkan build dengan pesan jelas |
| File `data-n*` root-owned → `rm` gagal | wipe manual error `Operation not permitted` | wipe selalu via helper container `--user 0:0` (sudah di `mw`) |
| Versi GOST / paket warp berubah | build gagal | pin versi via ARG + fallback microsocks/dante, CI build berkala |

## 16. Milestone

- M1 (0.5 hari): Dockerfile + entrypoint + compose 1 node → 1 SOCKS `warp=on`.
- M2 (0.5 hari): generator N + healthcheck + export-pool → 3 node hijau di VPS.
- M3 (1 hari): `mw` run/status/recreate + uji restart/reboot + dokumen README.
- M4 (tergantung host): scale 10 + recreate-loop sampai unik maksimal → `warp-pool.txt` final.
- M5 (fase 2): auth, HTTP proxy, exporter.

## 17. Open questions (butuh jawaban user sebelum/saat build)

1. WARP gratis cukup, atau ada license WARP+ / akun Zero Trust yang mau dipakai? (1 license bisa dipakai di semua 10 node atau per node beda?)
2. SOCKS perlu auth user/pass? Akses hanya dari localhost atau dari mesin lain (farm/Tailscale)?
3. Host final 10 node di VPS ini atau host lain yang RAM ≥4 GB? (menentukan M4)
4. Perlu HTTP proxy juga atau SOCKS5 saja?
5. Arsitektur cukup amd64, atau perlu arm64 juga?

---

## 18. Amendemen 2026-10-10 — mode IPv6-only (V6ONLY=1, default)

- Temuan: IPv4 egress WARP gratis = anycast shared (`104.28.x.x` sama di semua
  node) dan TIDAK bisa dibuat variatif — keterbatasan provider, bukan bug.
  `api.ipify.org` itu IPv4-only (tanpa AAAA) sehingga selalu terlihat "IPv4
  tidak variatif" bila dipakai untuk cek.
- Keputusan: tiap container menolak egress IPv4 lewat tunnel via nft
  (`entrypoint.sh: apply_v6only`, env `V6ONLY`, default `1`):
  `udp/tcp dport 53 accept` (DNS) → `tcp reject with tcp reset` →
  `generic reject`, di atas rule accept bawaan warp-svc; watchdog 60 dtk
  memasang ulang bila daemon menulis ulang tabel saat reconnect.
- Hasil verifikasi: 10/10 `warp=on`, 10 IPv6 unik stabil (3 ronde),
  domain IPv4-only fail-fast (`connection refused`), bukan bocor ke IPv4 shared.
- Nonaktifkan: `V6ONLY=0` di `.env` + rebuild.

---

## Lampiran A — `.env.example`

```bash
COUNT=10
BASE_PORT=40000
BIND=127.0.0.1
WARP_SLEEP=5
WARP_LICENSE_KEY=
MAX_ROUNDS=3
V6ONLY=1
```

## Lampiran B — `warp-pool.txt` (contoh hasil)

```text
socks5://127.0.0.1:40001
socks5://127.0.0.1:40002
socks5://127.0.0.1:40003
socks5://127.0.0.1:40004
socks5://127.0.0.1:40005
socks5://127.0.0.1:40006
socks5://127.0.0.1:40007
socks5://127.0.0.1:40008
socks5://127.0.0.1:40009
socks5://127.0.0.1:40010
```
