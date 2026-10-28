# syntax=docker/dockerfile:1.7

# Dedicated DockHosting runtime for luinog1/remux-render.
# The Remux Rust binary is prebuilt by GitHub Actions and published as a release
# asset in this repository. DockHosting only assembles the runtime image.

FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

ARG TARGETARCH
ARG REMUX_ASSETS_VERSION=0.38.2
ARG REMUX_BINARY_TAG=dockhosting-bin

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

RUN test "${TARGETARCH}" = "amd64" \
    && printf 'Acquire::ForceIPv4 "true";\n' > /etc/apt/apt.conf.d/99force-ipv4 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg libfontconfig1 libfreetype6 libssl3 tar \
        sqlite3 mariadb-client \
    && mkdir -p /etc/apt/keyrings \
    && curl -4 -fsSL --retry 8 --retry-all-errors \
        https://repo.jellyfin.org/jellyfin_team.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/jellyfin.gpg \
    && printf "Types: deb\nURIs: https://repo.jellyfin.org/debian\nSuites: trixie\nComponents: main\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/jellyfin.gpg\n" "${TARGETARCH}" \
        > /etc/apt/sources.list.d/jellyfin.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends jellyfin-ffmpeg8 \
    && apt-get remove -y --autoremove gnupg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# The fixed release URL stays stable. On the very first setup the GitHub Action
# may still be compiling while DockHosting starts its auto-deploy, so retry the
# binary download for up to 20 minutes instead of failing on a temporary 404.
RUN curl -4 -fL \
        --retry 60 --retry-delay 15 --retry-all-errors --retry-max-time 1200 \
        --connect-timeout 20 \
        "https://github.com/luinog1/remux-render/releases/download/${REMUX_BINARY_TAG}/remux-server-linux-amd64" \
        -o /app/remux-server \
    && chmod +x /app/remux-server

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

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY remux-backup.sh /usr/local/bin/remux-backup.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/remux-backup.sh \
    && mkdir -p /data/logs /data/torrents \
    && chmod 0777 /data /data/logs /data/torrents

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
    CMD curl -4 -fsS "http://127.0.0.1:${PORT}/health" || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
