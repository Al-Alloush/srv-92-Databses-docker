# PostgreSQL Server - Quick Reference

## 📁 Files

- `docker-compose.yml` - PostgreSQL 16 + pgAdmin
- `postgres-manager.sh` - manage databases (interactive menu or CLI)
- `databases.conf` - the list of managed databases and their owner roles
- `databases/<db>/*.sql` - optional schema/seed scripts per database
- `init/01-create-databases.sql` - first-start hook (intentionally a no-op)
- `backup.sh` - daily backups (see `../BACKUP.md`)

Credentials come from `/srv/db/.env` (not in git):

```bash
POSTGRES_CONTAINER=postgresql_db
POSTGRES_USER=...            # admin
POSTGRES_PASSWORD=...
PG_PASSWORD_<ROLE>=...       # one per owner role, e.g. PG_PASSWORD_SCHREIBLY_DB_USER
```

## 🚀 Commands

```bash
./postgres-manager.sh                 # interactive menu

./postgres-manager.sh add myapp_dev_db          # new DB + role myapp_dev_user, password generated into .env
./postgres-manager.sh add myapp_db shared_user  # new DB with an explicit owner role ("-" = admin)
./postgres-manager.sh apply                     # create whatever in databases.conf is missing (safe, idempotent)
./postgres-manager.sh reset myapp_dev_db        # drop + recreate empty (offers a backup first)
./postgres-manager.sh drop myapp_dev_db         # drop permanently + remove from databases.conf
./postgres-manager.sh reset-all                 # wipe the data volume, recreate everything in databases.conf

./postgres-manager.sh list | test | sync-passwords | psql [db]
./postgres-manager.sh start | stop | status | logs
```

## ➕ Adding databases

Either run `add` (it updates `databases.conf` and `.env` for you), or by hand:

1. Add a line to `databases.conf`: `myapp_db   myapp_user`
2. Add `PG_PASSWORD_MYAPP_USER=...` to `/srv/db/.env`
3. Optionally put schema/seed files in `databases/myapp_db/01-schema.sql`, ...
   (run as the owner role, only when the database is freshly created/reset)
4. Run `./postgres-manager.sh apply`

## ⚠️ Notes

- `apply` never changes existing roles or databases; it only creates missing ones.
- `reset-all` refuses to start unless every owner role has a password in `.env`,
  because the roles are recreated from scratch.
- Pre-reset backups go to `backups/<db>/<db>_prereset_<timestamp>.dump`
  (restore with `pg_restore -d <db>`).

## 🔌 Connection

- Internal (docker network `internal`): `postgresql_db:5432`
- External: `localhost:5436`
- pgAdmin: http://localhost:8888

```yaml
spring:
  datasource:
    url: jdbc:postgresql://postgresql_db:5432/myapp_db
    username: myapp_user
    password: ${PG_PASSWORD_MYAPP_USER}
```
