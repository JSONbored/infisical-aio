#!/command/with-contenv bash
# shellcheck shell=bash
# shellcheck disable=SC2310,SC2312
set -euo pipefail

ENV_FILE="${AIO_ENV_FILE:-/config/aio/generated.env}"

ensure_env_file() {
	mkdir -p "$(dirname "${ENV_FILE}")"
	touch "${ENV_FILE}"
	chmod 600 "${ENV_FILE}"
}

load_generated_env() {
	ensure_env_file
	[[ -f ${ENV_FILE} ]] || return 0

	while IFS='=' read -r key raw_value; do
		[[ -z ${key} ]] && continue
		[[ ${key} =~ ^[A-Z0-9_]+$ ]] || continue
		if [[ -n ${!key+x} ]]; then
			continue
		fi
		decoded_value="$(
			node - "${raw_value}" <<'NODE'
const raw = process.argv[2];
try {
  process.stdout.write(JSON.parse(raw));
} catch {
  process.stdout.write(raw);
}
NODE
		)"
		export "${key}=${decoded_value}"
	done <"${ENV_FILE}"
}

set_env_value() {
	local key="$1"
	local value="$2"
	ensure_env_file
	node - "${ENV_FILE}" "${key}" "${value}" <<'NODE'
const fs = require("fs");
const [file, key, value] = process.argv.slice(2);
const line = `${key}=${JSON.stringify(value)}\n`;
let contents = "";
try {
  contents = fs.readFileSync(file, "utf8");
} catch {}
const pattern = new RegExp(`^${key}=.*$`, "m");
if (pattern.test(contents)) {
  contents = contents.replace(pattern, line.trimEnd());
  if (!contents.endsWith("\n")) contents += "\n";
} else {
  contents += line;
}
fs.writeFileSync(file, contents, { mode: 0o600 });
NODE
}

persist_if_missing() {
	local key="$1"
	local value="$2"
	ensure_env_file
	if ! grep -q "^${key}=" "${ENV_FILE}"; then
		set_env_value "${key}" "${value}"
	fi
}

uri_host_is_loopback() {
	local uri="$1"
	node - "${uri}" <<'NODE'
const value = process.argv[2];
try {
  const parsed = new URL(value);
  const host = (parsed.hostname || "").toLowerCase();
  process.exit(["127.0.0.1", "localhost", "::1"].includes(host) ? 0 : 1);
} catch {
  process.exit(1);
}
NODE
}

host_is_loopback() {
	local host="${1,,}"
	case "${host}" in
	127.0.0.1 | localhost | ::1)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

env_flag_is_true() {
	local value="${1-}"
	case "${value,,}" in
	1 | true | yes | on)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

env_flag_is_false() {
	local value="${1-}"
	case "${value,,}" in
	0 | false | no | off)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

smtp_points_to_bundled_mailpit() {
	local host="${SMTP_HOST-}"
	local port="${SMTP_PORT:-1025}"

	if [[ -z ${host} ]]; then
		return 0
	fi

	host_is_loopback "${host}" && [[ ${port} == "1025" ]]
}

bundled_mailpit_enabled() {
	if env_flag_is_false "${AIO_ENABLE_BUNDLED_MAILPIT:-true}"; then
		return 1
	fi

	smtp_points_to_bundled_mailpit
}

smtp_is_external_configured() {
	[[ -n ${SMTP_HOST-} ]] || return 1
	! bundled_mailpit_enabled
}

configure_bundled_mailpit_env() {
	if ! bundled_mailpit_enabled; then
		return 0
	fi

	export SMTP_HOST="${SMTP_HOST:-127.0.0.1}"
	export SMTP_PORT="${SMTP_PORT:-1025}"
	export SMTP_IGNORE_TLS="${SMTP_IGNORE_TLS:-true}"
	export SMTP_REQUIRE_TLS="${SMTP_REQUIRE_TLS:-false}"
	export SMTP_TLS_REJECT_UNAUTHORIZED="${SMTP_TLS_REJECT_UNAUTHORIZED:-false}"
	export SMTP_FROM_ADDRESS="${SMTP_FROM_ADDRESS:-no-reply@infisical.local}"
	export SMTP_FROM_NAME="${SMTP_FROM_NAME:-Infisical}"
}

uri_scheme() {
	local uri="$1"
	node - "${uri}" <<'NODE'
const value = process.argv[2];
try {
  const parsed = new URL(value);
  process.stdout.write((parsed.protocol || "").replace(/:$/, ""));
} catch {
  process.exit(1);
}
NODE
}

wait_for_tcp_endpoint() {
	local host="$1"
	local port="$2"
	local label="$3"
	local deadline=$((SECONDS + 300))

	until (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; do
		if ((SECONDS >= deadline)); then
			echo "Timed out waiting for ${label} on ${host}:${port}." >&2
			return 1
		fi
		echo "Waiting for ${label} on ${host}:${port}..."
		sleep 2
	done
}

wait_for_mailpit_ready() {
	if bundled_mailpit_enabled; then
		wait_for_tcp_endpoint "127.0.0.1" "1025" "Mailpit SMTP"
	fi
}

effective_db_connection_uri() {
	if [[ -n ${DB_CONNECTION_URI-} ]]; then
		printf '%s\n' "${DB_CONNECTION_URI}"
		return 0
	fi

	if [[ -n ${DB_HOST-} ]] || [[ -n ${DB_USER-} ]] || [[ -n ${DB_PASSWORD-} ]] || [[ -n ${DB_NAME-} ]]; then
		printf 'postgresql://%s:%s@%s:%s/%s\n' \
			"${DB_USER-}" \
			"${DB_PASSWORD-}" \
			"${DB_HOST-}" \
			"${DB_PORT:-5432}" \
			"${DB_NAME-}"
		return 0
	fi

	return 1
}

postgres_is_external() {
	local db_uri
	db_uri="$(effective_db_connection_uri 2>/dev/null || true)"
	[[ -n ${db_uri} ]] && ! uri_host_is_loopback "${db_uri}"
}

wait_for_postgres_ready() {
	local db_uri
	db_uri="$(effective_db_connection_uri 2>/dev/null || true)"
	if [[ -z ${db_uri} ]]; then
		echo "No PostgreSQL configuration was found." >&2
		return 1
	fi

	local deadline=$((SECONDS + 300))
	until pg_isready -d "${db_uri}" >/dev/null 2>&1; do
		if ((SECONDS >= deadline)); then
			echo "Timed out waiting for PostgreSQL." >&2
			return 1
		fi
		echo "Waiting for PostgreSQL to accept connections..."
		sleep 2
	done
}

redis_connection_mode() {
	if [[ -n ${REDIS_URL-} ]]; then
		printf 'url\n'
		return 0
	fi

	if [[ -n ${REDIS_SENTINEL_HOSTS-} ]]; then
		printf 'sentinel\n'
		return 0
	fi

	if [[ -n ${REDIS_CLUSTER_HOSTS-} ]]; then
		printf 'cluster\n'
		return 0
	fi

	printf 'none\n'
}

redis_first_host() {
	local list="$1"
	local first="${list%%,*}"
	printf '%s\n' "${first%%:*}"
}

redis_first_port() {
	local list="$1"
	local first="${list%%,*}"
	if [[ ${first} == *:* ]]; then
		printf '%s\n' "${first##*:}"
		return 0
	fi

	printf '6379\n'
}

build_redis_tls_args() {
	local use_tls="$1"
	local -n target_ref="$2"
	target_ref=()

	if [[ ${use_tls} != "true" ]]; then
		return 0
	fi

	target_ref+=(--tls)
	if [[ -n ${NODE_EXTRA_CA_CERTS-} ]]; then
		target_ref+=(--cacert "${NODE_EXTRA_CA_CERTS}")
	fi
}

redis_ready_probe() {
	local mode="${1:-$(redis_connection_mode)}"
	local -a tls_args=()
	local -a auth_args=()
	local host=""
	local port=""
	local output=""

	case "${mode}" in
	url)
		if [[ -n ${REDIS_USERNAME-} ]]; then
			auth_args+=(--user "${REDIS_USERNAME}")
		fi
		if [[ -n ${REDIS_PASSWORD-} ]]; then
			auth_args+=(-a "${REDIS_PASSWORD}")
		fi

		if [[ $(uri_scheme "${REDIS_URL}") == "rediss" ]]; then
			build_redis_tls_args "true" tls_args
		fi

		redis-cli "${tls_args[@]}" "${auth_args[@]}" -u "${REDIS_URL}" ping 2>/dev/null | grep -qx "PONG"
		;;
	sentinel)
		host="$(redis_first_host "${REDIS_SENTINEL_HOSTS}")"
		port="$(redis_first_port "${REDIS_SENTINEL_HOSTS}")"
		build_redis_tls_args "${REDIS_SENTINEL_ENABLE_TLS:-false}" tls_args

		if [[ -n ${REDIS_SENTINEL_USERNAME-} ]]; then
			auth_args+=(--user "${REDIS_SENTINEL_USERNAME}")
		fi
		if [[ -n ${REDIS_SENTINEL_PASSWORD-} ]]; then
			auth_args+=(-a "${REDIS_SENTINEL_PASSWORD}")
		fi

		output="$(redis-cli "${tls_args[@]}" "${auth_args[@]}" \
			-h "${host}" \
			-p "${port}" \
			SENTINEL get-master-addr-by-name "${REDIS_SENTINEL_MASTER_NAME:-mymaster}" 2>/dev/null || true)"
		[[ -n ${output} ]]
		;;
	cluster)
		host="$(redis_first_host "${REDIS_CLUSTER_HOSTS}")"
		port="$(redis_first_port "${REDIS_CLUSTER_HOSTS}")"
		build_redis_tls_args "${REDIS_CLUSTER_ENABLE_TLS:-false}" tls_args

		if [[ -n ${REDIS_USERNAME-} ]]; then
			auth_args+=(--user "${REDIS_USERNAME}")
		fi
		if [[ -n ${REDIS_PASSWORD-} ]]; then
			auth_args+=(-a "${REDIS_PASSWORD}")
		fi

		redis-cli -c "${tls_args[@]}" "${auth_args[@]}" \
			-h "${host}" \
			-p "${port}" \
			ping 2>/dev/null | grep -qx "PONG"
		;;
	*)
		return 1
		;;
	esac
}

wait_for_redis_ready() {
	local mode
	mode="$(redis_connection_mode)"
	if [[ ${mode} == "none" ]]; then
		echo "No Redis configuration was found." >&2
		return 1
	fi

	local deadline=$((SECONDS + 300))
	until redis_ready_probe "${mode}"; do
		if ((SECONDS >= deadline)); then
			echo "Timed out waiting for Redis." >&2
			return 1
		fi
		echo "Waiting for Redis to accept connections..."
		sleep 2
	done
}
