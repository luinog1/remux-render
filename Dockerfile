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

ENV HOST=0.0.0.0 \
    PORT=3000 \
    DATA_DIR=/tmp/remux \
    DATABASE_URL=sqlite:///tmp/remux/db.sqlite?mode=rwc \
    LOG_FILE=/tmp/remux/logs/remux.jsonl \
    TORRENT_DATA_DIR=/tmp/remux/torrents \
    WEB_PATH=/app/jellyfin-web \
    DASHBOARD_PATH=/app/dashboard

WORKDIR /app

COPY --from=server-builder /src/target/release/remux-server /app/remux-server

# Free-tier test mode: no persistent volume is required.
RUN mkdir -p /tmp/remux/logs /tmp/remux/torrents \
    && chmod -R 777 /tmp/remux

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:3000/health" || exit 1

CMD ["./remux-server"]
