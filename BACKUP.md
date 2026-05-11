# Database Backups

Daily, automated backups of selected databases in the `mssql_db` and
`postgresql_db` containers. Runs as systemd timers on the host. Output lands
in per-database subfolders under each engine's `backups/` folder.

---

## 1. What gets backed up

The set of databases to back up is controlled by **two allowlists** in
`/srv/db/.env`:

| Variable | Current value | What it means |
| -------- | ------------- | ------------- |
| `MSSQL_DATABASES` | `imeterrecorder_db` | Only the iMeterRecorder **prod** DB. |
| `POSTGRES_DATABASES` | `keycloak_db` | Only the Keycloak prod DB. |

If you leave either variable empty, the corresponding script falls back to
auto-discovery and backs up **every** non-system database. With the
allowlists set, dev/test databases (`*_dev_db`, `*_test_db`) and
`server_driven_ui*` are intentionally **not** backed up.

### MSSQL (`mssql_db`)

`/srv/db/mssql/backup.sh` runs `BACKUP DATABASE` inside the container with
`INIT, FORMAT, CHECKSUM`, then gzips the `.bak` inside the container.

```
/srv/db/mssql/backups/
└── imeterrecorder_db/
    ├── imeterrecorder_db_20260430_023000.bak.gz
    ├── imeterrecorder_db_20260501_023000.bak.gz
    └── ...
```

### PostgreSQL (`postgresql_db`)

`/srv/db/postgres/backup.sh` produces two artifacts per run:

| File | What it is | How to restore |
| ---- | ---------- | -------------- |
| `_globals/_globals_YYYYMMDD_HHMMSS.sql.gz` | `pg_dumpall --globals-only` — roles, tablespaces. **Required** for full DR. | `gunzip -c <file> \| psql -U postgres` |
| `<dbname>/<dbname>_YYYYMMDD_HHMMSS.dump`   | `pg_dump -Fc -Z 6` — custom format, compressed. | `pg_restore -d <db> <file>` |

```
/srv/db/postgres/backups/
├── _globals/
│   └── _globals_YYYYMMDD_HHMMSS.sql.gz
└── keycloak_db/
    └── keycloak_db_YYYYMMDD_HHMMSS.dump
```

### File-count math (steady state at `RETENTION_DAYS=14`)

| Path | Files in flight |
| ---- | --------------- |
| `mssql/backups/imeterrecorder_db/` | 14 |
| `postgres/backups/keycloak_db/` | 14 |
| `postgres/backups/_globals/` | 14 |
| **Total** | **42** |

Adding a new DB to an allowlist adds **14 more files** at steady state.

---

## 2. Configuration — `/srv/db/.env`

All credentials and tunables live in **`/srv/db/.env`** (mode `600`,
gitignored). Both backup scripts source this file at start.

```bash
MSSQL_CONTAINER=mssql_db
MSSQL_SA_USER=sa
MSSQL_SA_PASSWORD=...
MSSQL_DATABASES='imeterrecorder_db'           # space-separated; empty = all

POSTGRES_CONTAINER=postgresql_db
POSTGRES_USER=db_service_admin_username
POSTGRES_PASSWORD=...
POSTGRES_DATABASES='keycloak_db'              # space-separated; empty = all

RETENTION_DAYS=14
```

### Adding a database to the backup set

Edit `/srv/db/.env` and append to the allowlist:

```bash
MSSQL_DATABASES='imeterrecorder_db another_prod_db'
POSTGRES_DATABASES='keycloak_db another_db'
```

Takes effect on the next run. The new subfolder is created automatically
the first time it backs up.

### Removing a database from the backup set

Drop its name from the allowlist. **Existing files in its subfolder are
not auto-deleted** — remove the folder by hand if you want the disk space
back. For MSSQL, the files are root-owned, so use the container:

```bash
docker exec mssql_db rm -rf /var/opt/mssql/backups/<dbname>
rm -rf /srv/db/mssql/backups/<dbname>      # remove the empty host dir
rm -rf /srv/db/postgres/backups/<dbname>   # postgres is host-owned
```

> If you rotate a password in `docker-compose.yml`, update `.env` in the
> same change so backups keep working.

---

## 3. Schedule — systemd timers

| Unit | When | Runs |
| ---- | ---- | ---- |
| `db-backup-postgres.timer` | daily 02:00 (+0–5 min jitter) | `db-backup-postgres.service` → `postgres/backup.sh` |
| `db-backup-mssql.timer`    | daily 02:30 (+0–5 min jitter) | `db-backup-mssql.service` → `mssql/backup.sh` |

`Persistent=true` is set on both, so if the host is off at the scheduled
time, the backup runs on the next boot.

Unit source files live in `/srv/db/systemd/` (version-controlled). The
installer copies them to `/etc/systemd/system/`.

### First-time install

```bash
sudo /srv/db/systemd/install.sh
```

### After editing any `.service` / `.timer` file

```bash
sudo /srv/db/systemd/install.sh   # idempotent: re-installs + daemon-reload
```

### Disable / re-enable

```bash
sudo systemctl disable --now db-backup-postgres.timer db-backup-mssql.timer
sudo systemctl enable  --now db-backup-postgres.timer db-backup-mssql.timer
```

---

## 4. How to check it is working

### Show next run + last run for each timer

```bash
systemctl list-timers 'db-backup-*'
```

### Status of the most recent run

```bash
systemctl status db-backup-postgres.service
systemctl status db-backup-mssql.service
```

(`Active: inactive (dead)` with `status=0/SUCCESS` is the expected idle
state for a `Type=oneshot` service that finished cleanly.)

### Live log (journald)

```bash
journalctl -u db-backup-postgres.service -n 50 --no-pager
journalctl -u db-backup-mssql.service    -n 50 --no-pager

# Follow next run as it happens:
journalctl -u 'db-backup-*.service' -f
```

### Per-script log files

Each script appends to its own log so you can read history without
journalctl:

```bash
tail -n 50 /srv/db/postgres/backups/backup.log
tail -n 50 /srv/db/mssql/backups/backup.log
```

### List actual backup files

```bash
ls -lh /srv/db/mssql/backups/imeterrecorder_db/
ls -lh /srv/db/postgres/backups/keycloak_db/
ls -lh /srv/db/postgres/backups/_globals/
```

Or a tree-style view of everything:

```bash
find /srv/db/{mssql,postgres}/backups -type f -printf '%TY-%Tm-%Td %TH:%TM  %s  %p\n' | sort
```

### Total disk usage per database

```bash
du -sh /srv/db/mssql/backups/*/   /srv/db/postgres/backups/*/
```

---

## 5. How to control it

### Run a backup immediately (out-of-schedule)

```bash
sudo systemctl start db-backup-postgres.service
sudo systemctl start db-backup-mssql.service
```

Or just call the script directly (no sudo needed — `devopsuser` is in the
`docker` group):

```bash
/srv/db/postgres/backup.sh
/srv/db/mssql/backup.sh
```

### Change the schedule

Edit the `OnCalendar=` line in the relevant `.timer` file under
`/srv/db/systemd/`, then re-run the installer:

```bash
sudo /srv/db/systemd/install.sh
```

`OnCalendar` syntax cheatsheet (use `man systemd.time` for full docs):

| Expression | Meaning |
| ---------- | ------- |
| `*-*-* 02:00:00` | every day at 02:00 |
| `Mon..Fri *-*-* 03:00:00` | weekdays at 03:00 |
| `*-*-* 00,06,12,18:00:00` | every 6 hours |
| `Sun *-*-* 04:00:00` | every Sunday at 04:00 |

Validate before installing:

```bash
systemd-analyze calendar '*-*-* 02:00:00'
```

### Change retention

Edit `RETENTION_DAYS` in `/srv/db/.env`. Takes effect on the **next** run
(rotation runs per-subfolder at the end of each backup).

To force a one-off rotation right now:

```bash
RETENTION_DAYS=7 /srv/db/postgres/backup.sh
RETENTION_DAYS=7 /srv/db/mssql/backup.sh
```

---

## 6. How to restore

### PostgreSQL — single database

```bash
# Copy the dump into the container
docker cp /srv/db/postgres/backups/keycloak_db/keycloak_db_YYYYMMDD_HHMMSS.dump \
          postgresql_db:/tmp/restore.dump

# Restore (creates objects; use --clean to drop first)
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i postgresql_db \
    pg_restore -U db_service_admin_username -h localhost \
               -d keycloak_db --clean --if-exists /tmp/restore.dump
```

For a brand-new cluster also load globals first:

```bash
gunzip -c /srv/db/postgres/backups/_globals/_globals_YYYYMMDD_HHMMSS.sql.gz \
  | docker exec -i postgresql_db psql -U db_service_admin_username -d postgres
```

### MSSQL — single database

```bash
# 1. Decompress (writes a root-owned .bak inside the container's mount)
docker exec mssql_db gunzip -k \
  /var/opt/mssql/backups/imeterrecorder_db/imeterrecorder_db_YYYYMMDD_HHMMSS.bak.gz

# 2. Restore (use REPLACE to overwrite an existing DB)
docker exec mssql_db /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
  -Q "RESTORE DATABASE [imeterrecorder_db]
      FROM DISK = N'/var/opt/mssql/backups/imeterrecorder_db/imeterrecorder_db_YYYYMMDD_HHMMSS.bak'
      WITH REPLACE, RECOVERY;"
```

> **Always test a restore periodically into a throwaway DB.** An untested
> backup is not a backup.

---

## 7. Files at a glance

```
/srv/db/
├── .env                          # ALL credentials + allowlists + retention (mode 600, gitignored)
├── BACKUP.md                     # this document
├── mssql/
│   ├── backup.sh                 # MSSQL backup script
│   └── backups/
│       ├── backup.log
│       └── <dbname>/             # one folder per backed-up DB
│           └── <dbname>_YYYYMMDD_HHMMSS.bak.gz
├── postgres/
│   ├── backup.sh                 # Postgres backup script
│   └── backups/
│       ├── backup.log
│       ├── _globals/
│       │   └── _globals_YYYYMMDD_HHMMSS.sql.gz
│       └── <dbname>/
│           └── <dbname>_YYYYMMDD_HHMMSS.dump
└── systemd/
    ├── db-backup-postgres.service
    ├── db-backup-postgres.timer
    ├── db-backup-mssql.service
    ├── db-backup-mssql.timer
    └── install.sh                # sudo-run installer (copies units to /etc/systemd/system)
```

---

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| `ERROR: container 'X' is not running` | Docker container down | `cd /srv/db/<engine> && docker compose up -d` |
| `ERROR: cannot read env file` | `.env` missing or wrong perms | `ls -la /srv/db/.env` — must exist and be readable by `devopsuser` |
| MSSQL: login fails | `MSSQL_SA_PASSWORD` in `.env` differs from compose | sync them |
| Postgres: `password authentication failed` | `POSTGRES_PASSWORD` in `.env` differs from compose | sync them |
| `FAIL: <db>` for a name in the allowlist | typo, or DB doesn't exist | check the spelling in `MSSQL_DATABASES` / `POSTGRES_DATABASES` |
| Timer never fires | Timer not enabled | `systemctl is-enabled db-backup-*.timer` — re-run installer |
| Backups fill the disk | Retention too high or many DBs | lower `RETENTION_DAYS` in `.env`, or shrink the allowlist |
