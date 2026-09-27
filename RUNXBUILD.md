# RunxBuild deployment

This repository now includes a root `Dockerfile` specifically for RunxBuild.

## RunxBuild settings

Create a **Web Service** from this GitHub repository and use:

- Production branch: `main`
- Build type: `Docker`
- Build command: empty
- Predeploy command: empty
- Output directory: empty
- Start command: empty
- HTTP port: use the platform-provided `PORT`

RunxBuild automatically builds the root `Dockerfile` and uses its `CMD`.

## Persistent data

Enable **Persistent Storage** for the service and mount the volume at:

```
/data
```

The Remux configuration/database is already configured for this path:

```
DATABASE_URL=sqlite:///data/db.sqlite?mode=rwc
DATA_DIR=/data
LOG_FILE=/data/logs/remux.jsonl
TORRENT_DATA_DIR=/data/torrents
```

Do not move the database outside `/data`, otherwise it will be lost when the service is replaced.

## What this Dockerfile does

The repository's normal Docker workflow expects pre-built `remux-server`, dashboard and Jellyfin Web artifacts. That is inconvenient for a platform that builds directly from GitHub.

The new root Dockerfile:

1. builds `remux-server` from this fork;
2. reuses the official Remux runtime image for ffmpeg, dashboard and Jellyfin Web assets;
3. replaces the runtime server binary with the binary built from this repository;
4. keeps all mutable application data under `/data`.

This avoids rebuilding the large Jellyfin Web and dashboard projects inside every RunxBuild deployment.

## First test

After the service is live, check:

```
/health
```

Then open the service URL. The Remux admin UI is normally available at:

```
/admin/
```

Create the initial account/library configuration and restart/redeploy the service. The SQLite database at `/data/db.sqlite` should remain intact because `/data` is the persistent mount.

## Important free-tier limitation

RunxBuild's current Starter plan includes 350 instance-hours/month and 120 GB/month bandwidth. Its pricing page lists databases as unlimited, but that refers to managed database instances; this Remux build uses SQLite on the service's persistent storage instead.

Persistent storage is listed separately as usage-based storage, so verify the storage charge shown by the RunxBuild dashboard before treating this setup as permanently zero-cost.
