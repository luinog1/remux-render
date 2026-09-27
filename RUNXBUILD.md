# RunxBuild deployment

This repository is prepared for RunxBuild with Remux state stored under /data.

## Persistence layout

RunxBuild Persistent Storage should be attached to:

    /data

The Dockerfile already configures Remux to use the persistent path:

    DATA_DIR=/data
    DATABASE_URL=sqlite:///data/db.sqlite?mode=rwc
    LOG_FILE=/data/logs/remux.jsonl
    TORRENT_DATA_DIR=/data/torrents

The SQLite database at /data/db.sqlite is the important state store: users, addons, libraries, settings, and other Remux configuration are persisted there.

Transcode-session files and torrent data are also placed below /data.

## RunxBuild service settings

Create/use a Web Service from this repository with:

- Production branch: main
- Build type: Docker
- Build command: empty
- Predeploy command: empty
- Output directory: empty
- Start command: empty

RunxBuild builds the root Dockerfile and uses its Docker CMD.

Do not override PORT. RunxBuild supplies the runtime service port.

The Dockerfile binds Remux to:

    HOST=0.0.0.0

and exposes container port 3000.

## Persistent Storage

Add a Persistent Storage volume in RunxBuild.

Use the storage path:

    /data

No application data should be configured under /app/data or /tmp/remux.

At container startup the Dockerfile creates:

    /data/logs
    /data/torrents

after the persistent volume is mounted.

## Environment variables

The persistence-related variables are already built into the image, so they do not need to be entered manually in RunxBuild.

The effective values are:

    DATA_DIR=/data
    DATABASE_URL=sqlite:///data/db.sqlite?mode=rwc
    LOG_FILE=/data/logs/remux.jsonl
    TORRENT_DATA_DIR=/data/torrents

Do not replace these with /app/data or /tmp/remux.

## First deployment

After deploying with Persistent Storage attached, verify:

    /health
    /admin/

Then create/configure the Remux users, addons and libraries.

To verify persistence, restart/redeploy the service without deleting the Persistent Storage volume. The same SQLite database at /data/db.sqlite must be reused, so Remux should come back with the existing configuration.

## Important: Persistent Storage does not prevent OOM

Persistent Storage protects the database/configuration from container replacement. It does not increase the service RAM limit.

The free RunxBuild instance previously reached:

    OOMKilled (exit 137)

during heavy library-refresh activity. If that happens again, the container can restart, but the Remux state stored in /data remains intact as long as the Persistent Storage volume is preserved.

For the 512 MB free instance, consider disabling expensive startup refresh tasks while testing:

    DISABLE_STARTUP_TASKS=true

This variable is optional and is not required for persistence.

## Data migration from the previous ephemeral deployment

If the previous deployment used /app/data, its database was outside the RunxBuild Persistent Storage path and therefore was ephemeral.

After switching to /data, the old database is not automatically copied. A migration requires access to the old db.sqlite file before the old container/data is discarded.

