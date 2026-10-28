# syntax=docker/dockerfile:1.7

# Azure VM image for luinog1/remux-render.
# Build the current forked remux-server, while reusing the upstream Remux
# runtime image for ffmpeg, dashboard, Jellyfin Web, and runtime libraries.

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

# The Azure VM mounts /opt/remux-data from the host at /data.
# Keep every persistent Remux file under /data so replacing the container/image
# does not replace the SQLite database, logs, torrents, or application state.
ENV HOST=0.0.0.0 \
    PORT=3000 \
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

CMD ["/bin/sh", "-c", "mkdir -p /data/logs /data/torrents && exec /app/remux-server"]
