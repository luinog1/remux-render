# syntax=docker/dockerfile:1.7

# RunxBuild-ready image for luinog1/remux-render.
# The upstream Remux image supplies runtime libraries, ffmpeg, dashboard and
# Jellyfin Web assets; this image rebuilds only the forked remux-server.

FROM rust:bookworm AS server-builder

WORKDIR /src

RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY Cargo.toml Cargo.lock ./
COPY crates ./crates

ENV SQLX_OFFLINE=true

RUN cargo build --release --locked -p remux-server \
    && test -x /src/target/release/remux-server

FROM ghcr.io/lostb1t/remux:latest

# Do not set PORT here. RunxBuild injects the service port at runtime.
#
# RunxBuild persistent storage is mounted at /data, so every piece of Remux
# state that must survive redeploys/restarts needs to live below /data.
#
# The free RunxBuild instance is resource-constrained. RefreshLibrary has a
# StartupTrigger and can perform large catalog imports + metadata writes while
# the Jellyfin API is already serving requests. On a slow SQLite volume this
# can starve the API, producing the long query/pool waits seen in production.
# Keep the daily trigger enabled; users can also start a refresh manually from
# the Remux UI after the instance is idle.
ENV HOST=0.0.0.0 \
    DATA_DIR=/data \
    DATABASE_URL=sqlite:///data/db.sqlite?mode=rwc \
    LOG_FILE=/data/logs/remux.jsonl \
    TORRENT_DATA_DIR=/data/torrents \
    WEB_PATH=/app/jellyfin-web \
    DASHBOARD_PATH=/app/dashboard \
    DISABLE_STARTUP_TASKS=true

WORKDIR /app

COPY --from=server-builder /src/target/release/remux-server /app/remux-server

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:3000/health" || exit 1

# Create required directories after RunxBuild mounts the persistent /data volume,
# then start Remux. This avoids creating them only in an image layer that can be
# hidden by the runtime volume mount.
CMD ["/bin/sh", "-c", "mkdir -p /data/logs /data/torrents && exec /app/remux-server"]
