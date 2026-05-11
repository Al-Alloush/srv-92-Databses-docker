#!/usr/bin/env bash
###############################################################################
# Install (or update) the db-backup systemd units.
#
# Run with sudo:
#     sudo /srv/db/systemd/install.sh
#
# Idempotent: rerun any time you edit the unit files in this folder.
###############################################################################
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (use sudo)" >&2
    exit 1
fi

SRC="/srv/db/systemd"
DEST="/etc/systemd/system"
UNITS=(
    "db-backup-postgres.service"
    "db-backup-postgres.timer"
    "db-backup-mssql.service"
    "db-backup-mssql.timer"
)

echo "==> Installing units to ${DEST}"
for unit in "${UNITS[@]}"; do
    install -m 0644 "${SRC}/${unit}" "${DEST}/${unit}"
    echo "    installed ${unit}"
done

echo "==> Reloading systemd"
systemctl daemon-reload

echo "==> Enabling + starting timers"
systemctl enable --now db-backup-postgres.timer db-backup-mssql.timer

echo "==> Done. Active timers:"
systemctl list-timers --no-pager 'db-backup-*'
