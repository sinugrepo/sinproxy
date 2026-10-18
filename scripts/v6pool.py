#!/usr/bin/env python3
"""v6pool — verifikasi tiap node tampil beda IP di sisi opencode.ai.

Entrypoint sudah pin IPv6 opencode.ai di /etc/hosts tiap container
(V6PIN_HOSTS), jadi request selalu egress via IPv6 unik per node.

Usage:
  python3 v6pool.py check          # trace via opencode.ai 1x per node + tulis v6pool.json
  python3 v6pool.py check -r 5      # ulangi 5x per node (uji stabilitas)
"""
import json, subprocess, sys

BASE, BIND, NODES = 40000, "127.0.0.1", 10
TRACE_URL = "https://opencode.ai/cdn-cgi/trace"
STATE = "v6pool.json"

def trace(n):
    r = subprocess.run(
        ["curl", "-s", "--max-time", "15", "--socks5-hostname",
         f"{BIND}:{BASE+n}", TRACE_URL],
        capture_output=True, text=True, timeout=30)
    ip = warp = "?"
    for line in r.stdout.splitlines():
        if line.startswith("ip="): ip = line[3:]
        elif line.startswith("warp="): warp = line[5:]
    return ip, warp

def main():
    rounds = 1
    if "-r" in sys.argv:
        rounds = int(sys.argv[sys.argv.index("-r") + 1])
    res = {}
    for n in range(1, NODES + 1):
        ips, warps = set(), set()
        for _ in range(rounds):
            ip, warp = trace(n)
            ips.add(ip); warps.add(warp)
        st = "OK" if len(ips) == 1 and "?" not in ips and warps == {"on"} else "FAIL"
        res[f"warp-n{n}"] = {"status": st, "egress": sorted(ips), "warp": sorted(warps)}
        print(f"warp-n{n}: {st} egress={sorted(ips)} warp={sorted(warps)}")
    allips = [v["egress"][0] for v in res.values() if v["status"] == "OK" and len(v["egress"]) == 1]
    print(f"--- {sum(1 for v in res.values() if v['status']=='OK')}/{NODES} OK, "
          f"{len(set(allips))} IP unik ---")
    json.dump(res, open(STATE, "w"), indent=1)
    print(f"wrote {STATE}")

if __name__ == "__main__":
    main()
