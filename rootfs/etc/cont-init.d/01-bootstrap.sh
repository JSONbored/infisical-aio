#!/command/with-contenv bash
# shellcheck shell=bash
set -euo pipefail

source /usr/local/bin/env-helpers.sh

ensure_env_file
load_generated_env

mkdir -p /config/aio /data/postgres /data/redis /run/postgresql
chown -R postgres:postgres /data/postgres /run/postgresql
chown -R redis:redis /data/redis
chmod 700 /data/postgres /data/redis

persist_if_missing "NODE_ENV" "production"
persist_if_missing "HOST" "0.0.0.0"
persist_if_missing "PORT" "8080"
persist_if_missing "TELEMETRY_ENABLED" "false"
persist_if_missing "SMTP_FROM_NAME" "Infisical"

if [[ -z ${ENCRYPTION_KEY-} ]]; then
	persist_if_missing "ENCRYPTION_KEY" "$(openssl rand -hex 16)"
fi

if [[ -z ${AUTH_SECRET-} ]]; then
	persist_if_missing "AUTH_SECRET" "$(openssl rand -base64 32)"
fi

if [[ -z ${DB_CONNECTION_URI-} ]] && [[ -z ${DB_HOST-} ]] && [[ -z ${DB_USER-} ]] && [[ -z ${DB_PASSWORD-} ]] && [[ -z ${DB_NAME-} ]]; then
	persist_if_missing "AIO_INTERNAL_DB_PASSWORD" "$(openssl rand -hex 24)"
	INTERNAL_PG_PASS="${AIO_INTERNAL_DB_PASSWORD:-$(grep '^AIO_INTERNAL_DB_PASSWORD=' "${ENV_FILE}" | cut -d= -f2- | tr -d '"')}"
	persist_if_missing "DB_CONNECTION_URI" "postgresql://infisical:${INTERNAL_PG_PASS}@127.0.0.1:5432/infisical"
fi

if [[ -z ${REDIS_URL-} ]] && [[ -z ${REDIS_SENTINEL_HOSTS-} ]] && [[ -z ${REDIS_CLUSTER_HOSTS-} ]]; then
	persist_if_missing "REDIS_URL" "redis://127.0.0.1:6379/0"
fi

echo "[infisical-aio] Generated first-run values are stored at ${ENV_FILE}."
