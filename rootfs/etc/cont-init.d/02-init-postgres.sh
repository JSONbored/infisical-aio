#!/command/with-contenv bash
# shellcheck shell=bash
set -euo pipefail

source /usr/local/bin/env-helpers.sh

load_generated_env

DB_CONNECTION_URI_VALUE="${DB_CONNECTION_URI-}"
if [[ -n ${DB_CONNECTION_URI_VALUE} ]] && ! uri_host_is_loopback "${DB_CONNECTION_URI_VALUE}"; then
	echo "[infisical-aio] External PostgreSQL detected. Skipping internal cluster bootstrap."
	exit 0
fi

mkdir -p /data/postgres /run/postgresql
chown -R postgres:postgres /data/postgres /run/postgresql
chmod 700 /data/postgres

if [[ -f /data/postgres/PG_VERSION ]]; then
	echo "[infisical-aio] Internal PostgreSQL cluster already initialized."
	exit 0
fi

PG_BIN_DIR="$(find /usr/lib/postgresql -mindepth 2 -maxdepth 2 -type d -name bin | sort | head -n 1)"
if [[ -z ${PG_BIN_DIR} ]]; then
	echo "Unable to locate PostgreSQL binaries under /usr/lib/postgresql." >&2
	exit 1
fi

if [[ -z ${AIO_INTERNAL_DB_PASSWORD-} ]]; then
	echo "AIO_INTERNAL_DB_PASSWORD was not generated." >&2
	exit 1
fi

echo "[infisical-aio] Initializing bundled PostgreSQL cluster..."
su -s /bin/bash postgres -c "${PG_BIN_DIR}/initdb -D /data/postgres"
su -s /bin/bash postgres -c "${PG_BIN_DIR}/pg_ctl -D /data/postgres -o \"-c listen_addresses='127.0.0.1'\" -w start"
su -s /bin/bash postgres -c "psql postgres <<'SQL'
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'infisical') THEN
        CREATE ROLE infisical LOGIN PASSWORD '${AIO_INTERNAL_DB_PASSWORD}';
    ELSE
        ALTER ROLE infisical WITH PASSWORD '${AIO_INTERNAL_DB_PASSWORD}';
    END IF;
END
\$\$;
SQL"
su -s /bin/bash postgres -c "psql postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='infisical'\" | grep -qx 1 || createdb -O infisical infisical"
su -s /bin/bash postgres -c "${PG_BIN_DIR}/pg_ctl -D /data/postgres -m fast -w stop"
