# syntax=docker/dockerfile:1.7

# DockHosting-specific image.
#
# DockHosting's builder is currently unreliable when pulling large layers from
# GHCR over IPv6. Keep this branch independent from Azure/main and avoid
# ghcr.io entirely during the build.
#
# We compile only this fork's remux-server. The matching static dashboard and
# Jellyfin Web UI are downloaded from the official Remux GitHub release over
# IPv4.

FROM rust:bookworm AS server-builder

WORKDIR /src

RUN printf 'Acquire::ForceIPv4 "true";\n' > /etc/apt/apt.conf.d/99force-ipv4 \
    && apt-get update \
    && apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY Cargo.toml Cargo.lock ./
COPY crates ./crates

ENV SQLX_OFFLINE=true

RUN cargo build --release --locked -p remux-server \
    && test -x /src/target/release/remux-server


FROM debian:trixie-slim

ARG TARGETARCH
ARG REMUX_ASSETS_VERSION=0.36.1

ENV DEBIAN_FRONTEND=noninteractive \
    HOST=0.0.0.0 \
    PORT=3000 \
    DATA_DIR=/data \
    DATABASE_URL=sqlite:///data/db.sqlite?mode=rwc \
    LOG_FILE=/data/logs/remux.jsonl \
    TORRENT_DATA_DIR=/data/torrents \
    WEB_PATH=/app/jellyfin-web \
    DASHBOARD_PATH=/app/dashboard \
    FFMPEG_PATH=/usr/lib/jellyfin-ffmpeg/ffmpeg \
    FFPROBE_PATH=/usr/lib/jellyfin-ffmpeg/ffprobe \
    PATH="/usr/lib/jellyfin-ffmpeg:${PATH}" \
    DISABLE_STARTUP_TASKS=true

# Force IPv4 inside the build as well. This also protects apt/curl downloads
# from the same IPv6 resets seen when DockHosting talks to GHCR.
RUN printf 'Acquire::ForceIPv4 "true";\n' > /etc/apt/apt.conf.d/99force-ipv4 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        python3 \
        python3-pip \
        libdrm2 \
        mesa-va-drivers \
        vainfo \
        libfontconfig1 \
        libfreetype6 \
        libssl3 \
        tar \
    && mkdir -p /etc/apt/keyrings \
    && curl -4 -fsSL --retry 8 --retry-all-errors \
        https://repo.jellyfin.org/jellyfin_team.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/jellyfin.gpg \
    && printf "Types: deb\nURIs: https://repo.jellyfin.org/debian\nSuites: trixie\nComponents: main\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/jellyfin.gpg\n" "${TARGETARCH}" \
        > /etc/apt/sources.list.d/jellyfin.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends jellyfin-ffmpeg8 \
    && pip3 install --break-system-packages yt-dlp "curl-cffi>=0.10,<0.15" \
    && apt-get remove -y --autoremove gnupg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Official Remux releases publish these static assets separately. Downloading
# them avoids pulling the large GHCR runtime image that is failing on
# DockHosting.
RUN mkdir -p /app/dashboard /app/jellyfin-web \
    && curl -4 -fL --retry 10 --retry-all-errors --connect-timeout 20 \
        "https://github.com/lostb1t/remux/releases/download/v${REMUX_ASSETS_VERSION}/remux-${REMUX_ASSETS_VERSION}-dashboard.tar.gz" \
        -o /tmp/dashboard.tar.gz \
    && curl -4 -fL --retry 10 --retry-all-errors --connect-timeout 20 \
        "https://github.com/lostb1t/remux/releases/download/v${REMUX_ASSETS_VERSION}/remux-${REMUX_ASSETS_VERSION}-jellyfin-web.tar.gz" \
        -o /tmp/jellyfin-web.tar.gz \
    && tar -xzf /tmp/dashboard.tar.gz -C /app/dashboard \
    && tar -xzf /tmp/jellyfin-web.tar.gz -C /app/jellyfin-web \
    && rm -f /tmp/dashboard.tar.gz /tmp/jellyfin-web.tar.gz \
    && test -n "$(find /app/dashboard -mindepth 1 -maxdepth 1 -print -quit)" \
    && test -n "$(find /app/jellyfin-web -mindepth 1 -maxdepth 1 -print -quit)"

COPY --from=server-builder /src/target/release/remux-server /app/remux-server

RUN mkdir -p /data/logs /data/torrents

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
    CMD curl -4 -fsS "http://127.0.0.1:${PORT}/health" || exit 1

CMD ["/bin/sh", "-c", "mkdir -p /data/logs /data/torrents && exec /app/remux-server"]
