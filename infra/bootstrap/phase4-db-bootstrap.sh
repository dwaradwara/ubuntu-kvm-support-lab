#!/bin/bash
set -euo pipefail

# shellcheck source=/dev/null
source /etc/phase4-db.env
: "${PHASE4_DB_PASSWORD:?PHASE4_DB_PASSWORD is required}"

PGCONF=/etc/postgresql/14/main/postgresql.conf
PGHBA=/etc/postgresql/14/main/pg_hba.conf

sed -ri \
  "s/^[#[:space:]]*listen_addresses[[:space:]]*=.*/listen_addresses = 'localhost,192.168.140.20'/" \
  "$PGCONF"

grep -qF \
  'host phase4app phase4_app 192.168.140.10/32 scram-sha-256' \
  "$PGHBA" || \
  echo 'host phase4app phase4_app 192.168.140.10/32 scram-sha-256' \
  >> "$PGHBA"

if runuser -u postgres -- psql -tAc \
  "SELECT 1 FROM pg_roles WHERE rolname='phase4_app'" \
  | grep -q 1; then

  runuser -u postgres -- psql \
    -c "ALTER ROLE phase4_app WITH LOGIN PASSWORD '${PHASE4_DB_PASSWORD}';"
else
  runuser -u postgres -- psql \
    -c "CREATE ROLE phase4_app LOGIN PASSWORD '${PHASE4_DB_PASSWORD}';"
fi

if ! runuser -u postgres -- psql -tAc \
  "SELECT 1 FROM pg_database WHERE datname='phase4app'" \
  | grep -q 1; then

  runuser -u postgres -- createdb \
    -O phase4_app phase4app
fi

runuser -u postgres -- psql \
  -v ON_ERROR_STOP=1 \
  -d phase4app <<'SQL'
SET ROLE phase4_app;

CREATE TABLE IF NOT EXISTS support_status (
    id integer PRIMARY KEY,
    message text NOT NULL
);

INSERT INTO support_status (id, message)
VALUES (1, 'database reachable')
ON CONFLICT (id)
DO UPDATE SET message = EXCLUDED.message;
SQL

systemctl restart postgresql
