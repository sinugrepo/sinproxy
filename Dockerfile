FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    WARP_SLEEP=5 \
    SOCKS_PORT=1080

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg lsb-release \
      dbus iproute2 iputils-ping nftables \
 && curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
      | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/cloudflare-client.list \
 && apt-get update && apt-get install -y --no-install-recommends cloudflare-warp \
 && rm -rf /var/lib/apt/lists/*

# GOST v3 SOCKS5 server (multi-arch: pakai TARGETARCH bawaan buildx)
ARG GOST_VER=3.3.0
ARG TARGETARCH
RUN GOST_ARCH="${TARGETARCH:-amd64}" \
 && if [ "$GOST_ARCH" = "arm64" ]; then GOST_FILE="gost_${GOST_VER}_linux_arm64.tar.gz"; \
    else GOST_FILE="gost_${GOST_VER}_linux_amd64.tar.gz"; fi \
 && curl -fsSL -o /tmp/gost.tgz "https://github.com/go-gost/gost/releases/download/v${GOST_VER}/${GOST_FILE}" \
 && tar -xzf /tmp/gost.tgz -C /usr/local/bin gost \
 && chmod +x /usr/local/bin/gost && rm /tmp/gost.tgz \
 && gost -V

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 1080

HEALTHCHECK --interval=60s --timeout=15s --start-period=120s --retries=3 \
  CMD curl -s --max-time 10 https://www.cloudflare.com/cdn-cgi/trace | grep -q warp=on || exit 1

ENTRYPOINT ["/entrypoint.sh"]
