#!/command/with-contenv bash
# shellcheck shell=bash
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/env-helpers.sh

MAILPIT_DIR="/config/aio/mailpit"
MAILPIT_UI_AUTH_FILE="${MAILPIT_DIR}/ui-auth.txt"

write_mailpit_ui_auth_file() {
	local username="$1"
	local password="$2"
	local salt
	local hashed_password

	salt="$(openssl rand -hex 8)"
	hashed_password="$(openssl passwd -6 -salt "${salt}" "${password}")"
	printf '%s:%s\n' "${username}" "${hashed_password}" >"${MAILPIT_UI_AUTH_FILE}"
	chown mailpit:mailpit "${MAILPIT_UI_AUTH_FILE}"
	chmod 600 "${MAILPIT_UI_AUTH_FILE}"
}

ensure_env_file
load_generated_env

mkdir -p /config/aio "${MAILPIT_DIR}" /data/postgres /data/redis /data/mailpit /run/postgresql
chown -R postgres:postgres /data/postgres /run/postgresql
chown -R redis:redis /data/redis
chown -R mailpit:mailpit "${MAILPIT_DIR}" /data/mailpit
chmod 700 "${MAILPIT_DIR}" /data/postgres /data/redis /data/mailpit

persist_if_missing "NODE_ENV" "production"
persist_if_missing "HOST" "0.0.0.0"
persist_if_missing "PORT" "8080"
persist_if_missing "TELEMETRY_ENABLED" "false"
persist_if_missing "SMTP_FROM_NAME" "Infisical"

if [[ -z ${ENCRYPTION_KEY-} ]]; then
	encryption_key="$(openssl rand -hex 16)"
	persist_if_missing "ENCRYPTION_KEY" "${encryption_key}"
fi

if [[ -z ${AUTH_SECRET-} ]]; then
	auth_secret="$(openssl rand -base64 32)"
	persist_if_missing "AUTH_SECRET" "${auth_secret}"
fi

if [[ -z ${DB_CONNECTION_URI-} ]] && [[ -z ${DB_HOST-} ]] && [[ -z ${DB_USER-} ]] && [[ -z ${DB_PASSWORD-} ]] && [[ -z ${DB_NAME-} ]]; then
	internal_db_password="$(openssl rand -hex 24)"
	persist_if_missing "AIO_INTERNAL_DB_PASSWORD" "${internal_db_password}"
	INTERNAL_PG_PASS="${AIO_INTERNAL_DB_PASSWORD-}"
	if [[ -z ${INTERNAL_PG_PASS} ]]; then
		INTERNAL_PG_PASS="$(grep '^AIO_INTERNAL_DB_PASSWORD=' "${ENV_FILE}" | cut -d= -f2- | tr -d '"')"
	fi
	persist_if_missing "DB_CONNECTION_URI" "postgresql://infisical:${INTERNAL_PG_PASS}@127.0.0.1:5432/infisical"
fi

if [[ -z ${REDIS_URL-} ]] && [[ -z ${REDIS_SENTINEL_HOSTS-} ]] && [[ -z ${REDIS_CLUSTER_HOSTS-} ]]; then
	persist_if_missing "REDIS_URL" "redis://127.0.0.1:6379/0"
fi

if bundled_mailpit_enabled; then
	mailpit_ui_username="${AIO_MAILPIT_UI_USERNAME:-infisical}"
	if [[ -z ${AIO_MAILPIT_UI_USERNAME-} ]]; then
		persist_if_missing "AIO_MAILPIT_UI_USERNAME" "${mailpit_ui_username}"
		export AIO_MAILPIT_UI_USERNAME="${mailpit_ui_username}"
	fi

	mailpit_ui_password="${AIO_MAILPIT_UI_PASSWORD-}"
	if [[ -z ${mailpit_ui_password} ]]; then
		mailpit_ui_password="$(openssl rand -base64 24 | tr -d '\n')"
		persist_if_missing "AIO_MAILPIT_UI_PASSWORD" "${mailpit_ui_password}"
		export AIO_MAILPIT_UI_PASSWORD="${mailpit_ui_password}"
	fi

	write_mailpit_ui_auth_file "${AIO_MAILPIT_UI_USERNAME}" "${AIO_MAILPIT_UI_PASSWORD}"
	echo "[infisical-aio] Bundled Mailpit UI credentials are stored at ${ENV_FILE} under AIO_MAILPIT_UI_USERNAME and AIO_MAILPIT_UI_PASSWORD."
fi

echo "[infisical-aio] Generated first-run values are stored at ${ENV_FILE}."
