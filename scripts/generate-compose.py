#!/usr/bin/env python3
"""Generate docker-compose.yml untuk N warp-socks node.
Usage: generate-compose.py -n 10 [--base-port 40000] [--bind 127.0.0.1] [-o docker-compose.yml]
"""
import argparse

SERVICE_TPL = """  warp-n{i}:
    build: .
    image: sinproxy/warp-socks:1.0
    container_name: warp-n{i}
    restart: unless-stopped
    mem_limit: 256m
    mem_reservation: 128m
    labels:
      - "autoheal=true"
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "2"
    device_cgroup_rules:
      - 'c 10:200 rwm'
    cap_add: [NET_ADMIN, MKNOD, AUDIT_WRITE]
    sysctls:
      net.ipv6.conf.all.disable_ipv6: 0
      net.ipv4.conf.all.src_valid_mark: 1
    ports:
      - "{bind}:{port}:1080"
    environment:
      - WARP_SLEEP=${{WARP_SLEEP:-5}}
      - V6PIN_HOSTS=${{V6PIN_HOSTS:-opencode.ai}}
      - V6ONLY=${{V6ONLY:-1}}
    volumes:
      - ./data-n{i}:/var/lib/cloudflare-warp
"""

AUTOHEAL_SVC = """  autoheal:
    image: willfarrell/autoheal:1.2.0
    container_name: sinproxy-autoheal
    restart: unless-stopped
    environment:
      - AUTOHEAL_CONTAINER_LABEL=autoheal
      - AUTOHEAL_INTERVAL=30
      - AUTOHEAL_START_PERIOD=0
      - AUTOHEAL_DEFAULT_STOP_TIMEOUT=30
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
"""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", "--count", type=int, default=10)
    ap.add_argument("--base-port", type=int, default=40000)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("-o", "--output", default="docker-compose.yml")
    a = ap.parse_args()

    out = ["services:"]
    for i in range(1, a.count + 1):
        out.append(SERVICE_TPL.format(i=i, bind=a.bind, port=a.base_port + i))
    out.append(AUTOHEAL_SVC)
    with open(a.output, "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"wrote {a.output}: {a.count} services, ports {a.bind}:{a.base_port+1}-{a.base_port+a.count}")

if __name__ == "__main__":
    main()
