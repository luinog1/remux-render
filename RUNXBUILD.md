# RunxBuild deployment

This repository includes a root `Dockerfile` for testing `remux-server` on RunxBuild.

## Current free-tier test mode

The Dockerfile intentionally uses a writable ephemeral directory:

```
DATA_DIR=/tmp/remux
DATABASE_URL=sqlite:///tmp/remux/db.sqlite?mode=rwc
LOG_FILE=/tmp/remux/logs/remux.jsonl
TORRENT_DATA_DIR=/tmp/remux/torrents
```

This is because the first RunxBuild test is being performed **without Persistent Storage**. The application can therefore boot and be tested, but the database/configuration will not survive replacement of the container.

Do **not** configure the service's `PORT` manually to another value. Let RunxBuild provide its runtime port; the image defaults to 3000.

## RunxBuild settings

Create a Web Service from this repository:

- Production branch: `main`
- Build type: `Docker`
- Build command: empty
- Predeploy command: empty
- Output directory: empty
- Start command: empty

RunxBuild builds the root `Dockerfile` and uses its `CMD`.

## Persistent mode later

When a Persistent Storage volume is available, mount it at:

```
/data
```

and set these environment variables in RunxBuild:

```
DATA_DIR=/data
DATABASE_URL=sqlite:///data/db.sqlite?mode=rwc
LOG_FILE=/data/logs/remux.jsonl
TORRENT_DATA_DIR=/data/torrents
```

The Remux server uses SQLite and expects the database to be writable at that location.

## First test

After deployment, verify:

```
/health
```

Then:

```
/admin/
```

The first test should confirm that the server starts, the dashboard is served, users can be created, and addons/libraries can be configured.

After a restart/replacement, the current free-tier test data is expected to be lost because it lives in `/tmp/remux`.
