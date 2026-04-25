#!/usr/bin/env bash
# shellcheck disable=SC2310
set -euo pipefail

IMAGE_TAG="${1:-infisical-aio:test}"
MATRIX_MODE="${2:-all}"
READY_LOG="${READY_LOG:-[infisical-aio] Infisical API is ready}"
HTTP_TIMEOUT_SECONDS="${HTTP_TIMEOUT_SECONDS:-300}"
START_TIMEOUT_SECONDS="${START_TIMEOUT_SECONDS:-300}"
POLL_SECONDS="${POLL_SECONDS:-2}"
RUN_ID="${RUN_ID:-${RANDOM}}"
NETWORK_NAME="${NETWORK_NAME:-infisical-aio-matrix-${RUN_ID}}"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/infisical-aio-matrix.XXXXXX")"
EXTERNAL_MAILPIT_IMAGE="${EXTERNAL_MAILPIT_IMAGE:-axllent/mailpit:v1.29.7}"

declare -a CONTAINERS=()

STARTED_APP_PORT=""
STARTED_MAILPIT_PORT=""
STARTED_METRICS_PORT=""

cleanup() {
	for container in "${CONTAINERS[@]}"; do
		docker rm -f "${container}" >/dev/null 2>&1 || true
	done
	docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
	rm -rf "${WORK_ROOT}"
}
trap cleanup EXIT

fail() {
	echo "ERROR: $*" >&2
	for container in "${CONTAINERS[@]}"; do
		echo >&2
		echo "--- logs: ${container} ---" >&2
		docker logs "${container}" >&2 || true
	done
	exit 1
}

register_container() {
	CONTAINERS+=("$1")
}

pick_free_port() {
	python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

wait_for_http() {
	local url="$1"
	local deadline=$((SECONDS + HTTP_TIMEOUT_SECONDS))
	until curl -fsS "${url}" >/dev/null 2>&1; do
		if ((SECONDS >= deadline)); then
			fail "Timed out waiting for ${url}"
		fi
		sleep "${POLL_SECONDS}"
	done
}

wait_for_log() {
	local container="$1"
	local pattern="$2"
	local deadline=$((SECONDS + START_TIMEOUT_SECONDS))

	while ((SECONDS < deadline)); do
		local logs
		logs="$(docker logs "${container}" 2>&1 || true)"
		if [[ ${logs} == *"${pattern}"* ]]; then
			return 0
		fi
		if ! docker ps --format '{{.Names}}' | grep -qx "${container}"; then
			fail "Container ${container} exited before emitting readiness log"
		fi
		sleep "${POLL_SECONDS}"
	done

	fail "Timed out waiting for ${container} log pattern: ${pattern}"
}

wait_for_exec_success() {
	local container="$1"
	local command="$2"
	local deadline=$((SECONDS + START_TIMEOUT_SECONDS))

	while ((SECONDS < deadline)); do
		if docker exec "${container}" sh -lc "${command}" >/dev/null 2>&1; then
			return 0
		fi
		sleep "${POLL_SECONDS}"
	done

	fail "Timed out waiting for ${container} command to succeed: ${command}"
}

wait_for_host_file() {
	local file="$1"
	local deadline=$((SECONDS + START_TIMEOUT_SECONDS))

	while ((SECONDS < deadline)); do
		if [[ -f ${file} ]]; then
			return 0
		fi
		sleep "${POLL_SECONDS}"
	done

	fail "Timed out waiting for file ${file}"
}

assert_file_contains_key() {
	local file="$1"
	local key="$2"
	grep -q "^${key}=" "${file}" || fail "Expected ${file} to contain ${key}"
}

assert_file_omits_key() {
	local file="$1"
	local key="$2"
	if grep -q "^${key}=" "${file}"; then
		fail "Expected ${file} to omit ${key}"
	fi
}

assert_process_present() {
	local container="$1"
	local pattern="$2"
	local processes
	processes="$(docker exec "${container}" sh -lc 'ps -eo comm=,args=' 2>/dev/null || true)"
	printf '%s\n' "${processes}" | grep -E "${pattern}" >/dev/null || fail "Expected ${container} to have process matching ${pattern}"
}

assert_process_absent() {
	local container="$1"
	local pattern="$2"
	local processes
	processes="$(docker exec "${container}" sh -lc 'ps -eo comm=,args=' 2>/dev/null || true)"
	if printf '%s\n' "${processes}" | grep -E "${pattern}" >/dev/null; then
		fail "Expected ${container} to keep process ${pattern} idle"
	fi
}

assert_log_contains() {
	local container="$1"
	local pattern="$2"
	local logs
	logs="$(docker logs "${container}" 2>&1 || true)"
	[[ ${logs} == *"${pattern}"* ]] || fail "Expected ${container} logs to contain: ${pattern}"
}

assert_valid_json_file() {
	local file="$1"
	python3 - "${file}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
if not payload:
    raise SystemExit("JSON payload was empty")
PY
}

assert_file_mode_is_600() {
	local file="$1"
	python3 - "${file}" <<'PY'
import os
import stat
import sys

mode = stat.S_IMODE(os.stat(sys.argv[1]).st_mode)
if mode != 0o600:
    raise SystemExit(f"Expected 0o600, got {oct(mode)}")
PY
}

assert_env_equals() {
	local container="$1"
	local key="$2"
	local expected="$3"
	docker exec "${container}" sh -lc "test \"\${${key}}\" = \"${expected}\"" >/dev/null 2>&1 || fail "Expected ${key} in ${container} to equal the supplied override"
}

read_env_file_value() {
	local file="$1"
	local key="$2"
	node - "${file}" "${key}" <<'NODE'
const fs = require("fs");
const [file, key] = process.argv.slice(2);
const contents = fs.readFileSync(file, "utf8");
for (const line of contents.split(/\r?\n/)) {
  if (!line.startsWith(`${key}=`)) continue;
  const raw = line.slice(key.length + 1);
  try {
    process.stdout.write(JSON.parse(raw));
  } catch {
    process.stdout.write(raw);
  }
  process.exit(0);
}
process.exit(1);
NODE
}

mailpit_api_request() {
	local host_port="$1"
	local username="${2-}"
	local password="${3-}"
	if [[ -n ${username} ]]; then
		curl -fsS -u "${username}:${password}" "http://127.0.0.1:${host_port}/api/v1/messages"
	else
		curl -fsS "http://127.0.0.1:${host_port}/api/v1/messages"
	fi
}

wait_for_mailpit_api() {
	local host_port="$1"
	local username="${2-}"
	local password="${3-}"
	local deadline=$((SECONDS + HTTP_TIMEOUT_SECONDS))

	until mailpit_api_request "${host_port}" "${username}" "${password}" >/dev/null 2>&1; do
		if ((SECONDS >= deadline)); then
			fail "Timed out waiting for Mailpit API on port ${host_port}"
		fi
		sleep "${POLL_SECONDS}"
	done
}

assert_mailpit_api_requires_auth() {
	local host_port="$1"
	local http_code
	http_code="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${host_port}/api/v1/messages")"
	[[ ${http_code} == "401" || ${http_code} == "403" ]] || fail "Expected Mailpit API on port ${host_port} to require authentication"
}

wait_for_mailpit_message() {
	local host_port="$1"
	local username="${2-}"
	local password="${3-}"
	local expected_recipient="$4"
	local expected_subject="$5"
	local deadline=$((SECONDS + START_TIMEOUT_SECONDS))

	while ((SECONDS < deadline)); do
		local payload
		payload="$(mailpit_api_request "${host_port}" "${username}" "${password}" 2>/dev/null || true)"
		if [[ ${payload} == *"${expected_recipient}"* && ${payload} == *"${expected_subject}"* ]]; then
			return 0
		fi
		sleep "${POLL_SECONDS}"
	done

	fail "Timed out waiting for Mailpit message for ${expected_recipient} with subject ${expected_subject}"
}

wait_for_infisical_ready() {
	local container="$1"
	local host_port="$2"
	local url="http://127.0.0.1:${host_port}/api/status"
	local deadline=$((SECONDS + HTTP_TIMEOUT_SECONDS))

	while ((SECONDS < deadline)); do
		local state
		state="$(docker inspect -f '{{.State.Status}}' "${container}" 2>/dev/null || true)"
		if [[ -n ${state} && ${state} != "running" ]]; then
			fail "${container} stopped before becoming ready"
		fi

		if curl -fsS "${url}" >/dev/null 2>&1; then
			return 0
		fi

		local logs
		logs="$(docker logs "${container}" 2>&1 || true)"
		if [[ ${logs} == *"${READY_LOG}"* ]]; then
			wait_for_http "${url}"
			return 0
		fi

		sleep "${POLL_SECONDS}"
	done

	fail "Timed out waiting for ${container} readiness via ${url}"
}

start_infisical() {
	local container="$1"
	local config_dir="$2"
	local data_dir="$3"
	local publish_mailpit="${4:-false}"
	local publish_metrics="${5:-false}"
	shift 5

	mkdir -p "${config_dir}" "${data_dir}"
	STARTED_APP_PORT="$(pick_free_port)"
	STARTED_MAILPIT_PORT=""
	STARTED_METRICS_PORT=""

	local -a docker_args=(
		-d
		--name "${container}"
		--network "${NETWORK_NAME}"
		-p "127.0.0.1:${STARTED_APP_PORT}:8080"
		-v "${config_dir}:/config"
		-v "${data_dir}:/data"
		-e "SITE_URL=http://127.0.0.1:${STARTED_APP_PORT}"
	)

	if [[ ${publish_mailpit} == "true" ]]; then
		STARTED_MAILPIT_PORT="$(pick_free_port)"
		docker_args+=(-p "127.0.0.1:${STARTED_MAILPIT_PORT}:8025")
	fi

	if [[ ${publish_metrics} == "true" ]]; then
		STARTED_METRICS_PORT="$(pick_free_port)"
		docker_args+=(-p "127.0.0.1:${STARTED_METRICS_PORT}:9464")
	fi

	docker run "${docker_args[@]}" "$@" "${IMAGE_TAG}" >/dev/null
	register_container "${container}"
}

start_external_mailpit() {
	local container="$1"

	STARTED_MAILPIT_PORT="$(pick_free_port)"
	docker run -d \
		--name "${container}" \
		--network "${NETWORK_NAME}" \
		-p "127.0.0.1:${STARTED_MAILPIT_PORT}:8025" \
		"${EXTERNAL_MAILPIT_IMAGE}" \
		--disable-wal \
		--disable-version-check \
		--block-remote-css-and-fonts \
		--smtp-disable-rdns >/dev/null
	register_container "${container}"
	wait_for_http "http://127.0.0.1:${STARTED_MAILPIT_PORT}/api/v1/messages"
}

start_external_postgres() {
	local container="$1"
	docker run -d \
		--name "${container}" \
		--network "${NETWORK_NAME}" \
		-e POSTGRES_USER=infisical \
		-e POSTGRES_PASSWORD=infisical \
		-e POSTGRES_DB=infisical \
		postgres:16 >/dev/null
	register_container "${container}"
	wait_for_exec_success "${container}" "pg_isready -U infisical -d infisical"
}

start_external_redis() {
	local container="$1"
	docker run -d \
		--name "${container}" \
		--network "${NETWORK_NAME}" \
		redis:7-alpine >/dev/null
	register_container "${container}"
	wait_for_exec_success "${container}" "redis-cli ping | grep -qx PONG"
}

start_external_redis_sentinel() {
	local master_container="$1"
	local sentinel_container="$2"
	local sentinel_config="${WORK_ROOT}/sentinel/sentinel.conf"

	mkdir -p "$(dirname "${sentinel_config}")"
	cat >"${sentinel_config}" <<EOF
bind 0.0.0.0
port 26379
protected-mode no
dir /tmp
sentinel monitor mymaster ${master_container} 6379 1
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 60000
sentinel parallel-syncs mymaster 1
sentinel resolve-hostnames yes
sentinel announce-hostnames yes
EOF

	docker run -d \
		--name "${master_container}" \
		--network "${NETWORK_NAME}" \
		redis:7-alpine >/dev/null
	register_container "${master_container}"
	wait_for_exec_success "${master_container}" "redis-cli ping | grep -qx PONG"

	docker run -d \
		--name "${sentinel_container}" \
		--network "${NETWORK_NAME}" \
		-v "${sentinel_config}:/seed/sentinel.conf:ro" \
		redis:7-alpine \
		sh -lc 'cp /seed/sentinel.conf /tmp/sentinel.conf && exec redis-server /tmp/sentinel.conf --sentinel' >/dev/null
	register_container "${sentinel_container}"
	wait_for_exec_success "${sentinel_container}" "redis-cli -h 127.0.0.1 -p 26379 SENTINEL get-master-addr-by-name mymaster | grep -q ${master_container}"
}

start_external_redis_cluster() {
	local prefix="$1"
	local -a nodes=("${prefix}-1" "${prefix}-2" "${prefix}-3")

	for node in "${nodes[@]}"; do
		docker run -d \
			--name "${node}" \
			--network "${NETWORK_NAME}" \
			redis:7-alpine \
			redis-server \
			--bind 0.0.0.0 \
			--protected-mode no \
			--port 6379 \
			--cluster-enabled yes \
			--cluster-config-file nodes.conf \
			--cluster-node-timeout 5000 \
			--appendonly no >/dev/null
		register_container "${node}"
		wait_for_exec_success "${node}" "redis-cli ping | grep -qx PONG"
	done

	docker exec "${nodes[0]}" sh -lc "yes yes | redis-cli --cluster create ${nodes[0]}:6379 ${nodes[1]}:6379 ${nodes[2]}:6379 --cluster-replicas 0" >/dev/null 2>&1 || fail "Failed to create Redis cluster"
	wait_for_exec_success "${nodes[0]}" "redis-cli -c -h ${nodes[0]} -p 6379 ping | grep -qx PONG"
}

generate_ca_material() {
	local cert_dir="$1"
	mkdir -p "${cert_dir}"

	openssl genrsa -out "${cert_dir}/ca.key" 2048 >/dev/null 2>&1
	openssl req -x509 -new -nodes -key "${cert_dir}/ca.key" -sha256 -days 1 \
		-subj "/CN=infisical-aio-test-ca" \
		-out "${cert_dir}/ca.crt" >/dev/null 2>&1

	openssl genrsa -out "${cert_dir}/server.key" 2048 >/dev/null 2>&1
	openssl req -new -key "${cert_dir}/server.key" \
		-subj "/CN=redis-tls-${RUN_ID}" \
		-out "${cert_dir}/server.csr" >/dev/null 2>&1

	cat >"${cert_dir}/server.ext" <<EOF
subjectAltName=DNS:redis-tls-${RUN_ID}
extendedKeyUsage=serverAuth
EOF

	openssl x509 -req \
		-in "${cert_dir}/server.csr" \
		-CA "${cert_dir}/ca.crt" \
		-CAkey "${cert_dir}/ca.key" \
		-CAcreateserial \
		-out "${cert_dir}/server.crt" \
		-days 1 \
		-sha256 \
		-extfile "${cert_dir}/server.ext" >/dev/null 2>&1
}

start_external_redis_tls() {
	local container="$1"
	local cert_dir="$2"

	docker run -d \
		--name "${container}" \
		--network "${NETWORK_NAME}" \
		-v "${cert_dir}:/certs:ro" \
		redis:7-alpine \
		redis-server \
		--bind 0.0.0.0 \
		--protected-mode no \
		--port 0 \
		--tls-port 6379 \
		--tls-auth-clients no \
		--tls-cert-file /certs/server.crt \
		--tls-key-file /certs/server.key \
		--tls-ca-cert-file /certs/ca.crt >/dev/null
	register_container "${container}"
	wait_for_exec_success "${container}" "redis-cli --tls --cacert /certs/ca.crt -h 127.0.0.1 -p 6379 ping | grep -qx PONG"
}

run_bundled_mode() {
	local container="infisical-aio-bundled-${RUN_ID}"
	local config_dir="${WORK_ROOT}/bundled/config"
	local data_dir="${WORK_ROOT}/bundled/data"
	local env_file
	local auth_file
	local before_hash
	local after_hash
	local mailpit_username
	local mailpit_password
	local mailpit_payload

	echo "== bundled mode =="
	start_infisical "${container}" "${config_dir}" "${data_dir}" true false
	wait_for_infisical_ready "${container}" "${STARTED_APP_PORT}"

	env_file="${config_dir}/aio/generated.env"
	auth_file="${config_dir}/aio/mailpit/ui-auth.txt"
	[[ -f ${env_file} ]] || fail "Expected ${env_file} to exist"
	assert_file_contains_key "${env_file}" "ENCRYPTION_KEY"
	assert_file_contains_key "${env_file}" "AUTH_SECRET"
	assert_file_contains_key "${env_file}" "AIO_INTERNAL_DB_PASSWORD"
	assert_file_contains_key "${env_file}" "AIO_MAILPIT_UI_USERNAME"
	assert_file_contains_key "${env_file}" "AIO_MAILPIT_UI_PASSWORD"
	assert_file_contains_key "${env_file}" "DB_CONNECTION_URI"
	assert_file_contains_key "${env_file}" "REDIS_URL"
	assert_file_contains_key "${env_file}" "TELEMETRY_ENABLED"
	wait_for_host_file "${auth_file}"
	assert_file_mode_is_600 "${auth_file}"

	assert_process_present "${container}" '^postgres(\s|$)|postgres -D /data/postgres'
	assert_process_present "${container}" '^redis-server(\s|$)'
	assert_process_present "${container}" '^mailpit(\s|$)'
	assert_log_contains "${container}" "SMTP - Verified connection to 127.0.0.1:1025"

	mailpit_username="$(read_env_file_value "${env_file}" "AIO_MAILPIT_UI_USERNAME")"
	mailpit_password="$(read_env_file_value "${env_file}" "AIO_MAILPIT_UI_PASSWORD")"
	assert_mailpit_api_requires_auth "${STARTED_MAILPIT_PORT}"
	wait_for_mailpit_api "${STARTED_MAILPIT_PORT}" "${mailpit_username}" "${mailpit_password}"
	mailpit_payload="$(mailpit_api_request "${STARTED_MAILPIT_PORT}" "${mailpit_username}" "${mailpit_password}")"
	[[ ${mailpit_payload} == *"messages"* ]] || fail "Expected Mailpit API payload to contain messages metadata"

	before_hash="$(shasum -a 256 "${env_file}" | awk '{print $1}')"
	docker restart "${container}" >/dev/null
	wait_for_http "http://127.0.0.1:${STARTED_APP_PORT}/api/status"
	wait_for_mailpit_api "${STARTED_MAILPIT_PORT}" "${mailpit_username}" "${mailpit_password}"
	after_hash="$(shasum -a 256 "${env_file}" | awk '{print $1}')"
	[[ ${before_hash} == "${after_hash}" ]] || fail "Expected ${env_file} to remain unchanged across restart"
}

run_manual_secret_override_mode() {
	local container="infisical-aio-manual-secrets-${RUN_ID}"
	local config_dir="${WORK_ROOT}/manual-secrets/config"
	local data_dir="${WORK_ROOT}/manual-secrets/data"
	local env_file="${config_dir}/aio/generated.env"
	local manual_encryption_key="0123456789abcdef0123456789abcdef"
	local manual_auth_secret="manual-auth-secret-value-for-local-validation-only"

	echo "== manual secret override mode =="
	start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		false \
		false \
		-e "ENCRYPTION_KEY=${manual_encryption_key}" \
		-e "AUTH_SECRET=${manual_auth_secret}"
	wait_for_infisical_ready "${container}" "${STARTED_APP_PORT}"

	wait_for_host_file "${env_file}"
	assert_file_omits_key "${env_file}" "ENCRYPTION_KEY"
	assert_file_omits_key "${env_file}" "AUTH_SECRET"
	assert_env_equals "${container}" "ENCRYPTION_KEY" "${manual_encryption_key}"
	assert_env_equals "${container}" "AUTH_SECRET" "${manual_auth_secret}"
}

run_bootstrap_mode() {
	local container="infisical-aio-bootstrap-${RUN_ID}"
	local config_dir="${WORK_ROOT}/bootstrap/config"
	local data_dir="${WORK_ROOT}/bootstrap/data"
	local marker_file="${config_dir}/aio/.bootstrap-complete"
	local response_file="${config_dir}/aio/bootstrap-response.json"
	local env_file="${config_dir}/aio/generated.env"
	local mailpit_username
	local mailpit_password
	local recovery_email="admin-${RUN_ID}@example.com"

	echo "== bootstrap mode =="
	start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		true \
		false \
		-e "AIO_BOOTSTRAP_EMAIL=admin-${RUN_ID}@example.com" \
		-e "AIO_BOOTSTRAP_PASSWORD=InfisicalAio-${RUN_ID}-Passw0rd!" \
		-e "AIO_BOOTSTRAP_ORGANIZATION=Infisical AIO Validation ${RUN_ID}" \
		-e "AIO_BOOTSTRAP_SAVE_RESPONSE=true"
	wait_for_infisical_ready "${container}" "${STARTED_APP_PORT}"

	wait_for_host_file "${marker_file}"
	wait_for_host_file "${response_file}"
	assert_file_mode_is_600 "${marker_file}"
	assert_file_mode_is_600 "${response_file}"
	assert_valid_json_file "${response_file}"
	assert_log_contains "${container}" "Instance bootstrap completed."

	mailpit_username="$(read_env_file_value "${env_file}" "AIO_MAILPIT_UI_USERNAME")"
	mailpit_password="$(read_env_file_value "${env_file}" "AIO_MAILPIT_UI_PASSWORD")"
	wait_for_mailpit_api "${STARTED_MAILPIT_PORT}" "${mailpit_username}" "${mailpit_password}"

	curl -fsS \
		-H 'Content-Type: application/json' \
		-d "{\"email\":\"${recovery_email}\"}" \
		-X POST "http://127.0.0.1:${STARTED_APP_PORT}/api/v1/account-recovery/send-email" >/dev/null
	wait_for_mailpit_message "${STARTED_MAILPIT_PORT}" "${mailpit_username}" "${mailpit_password}" "${recovery_email}" "Infisical account recovery"
}

run_external_postgres_uri_mode() {
	local postgres_container="infisical-aio-ext-postgres-uri-${RUN_ID}"
	local container="infisical-aio-app-ext-postgres-uri-${RUN_ID}"
	local config_dir="${WORK_ROOT}/external-postgres-uri/config"
	local data_dir="${WORK_ROOT}/external-postgres-uri/data"

	echo "== external postgres via DB_CONNECTION_URI mode =="
	start_external_postgres "${postgres_container}"
	start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		false \
		false \
		-e "DB_CONNECTION_URI=postgresql://infisical:infisical@${postgres_container}:5432/infisical"
	wait_for_infisical_ready "${container}" "${STARTED_APP_PORT}"

	assert_log_contains "${container}" "External PostgreSQL configured. Bundled PostgreSQL service staying idle."
	assert_process_absent "${container}" '^postgres(\s|$)|postgres -D /data/postgres'
	assert_process_present "${container}" '^redis-server(\s|$)'
}

run_external_postgres_field_mode() {
	local postgres_container="infisical-aio-ext-postgres-fields-${RUN_ID}"
	local container="infisical-aio-app-ext-postgres-fields-${RUN_ID}"
	local config_dir="${WORK_ROOT}/external-postgres-fields/config"
	local data_dir="${WORK_ROOT}/external-postgres-fields/data"
	local read_replica_json

	echo "== external postgres via DB_* fields mode =="
	start_external_postgres "${postgres_container}"
	read_replica_json="$(printf '[{\"DB_CONNECTION_URI\":\"postgresql://infisical:infisical@%s:5432/infisical\"}]' "${postgres_container}")"

	start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		false \
		false \
		-e "DB_HOST=${postgres_container}" \
		-e "DB_PORT=5432" \
		-e "DB_USER=infisical" \
		-e "DB_PASSWORD=infisical" \
		-e "DB_NAME=infisical" \
		-e "DB_READ_REPLICAS=${read_replica_json}"
	wait_for_infisical_ready "${container}" "${STARTED_APP_PORT}"

	assert_log_contains "${container}" "External PostgreSQL configured. Bundled PostgreSQL service staying idle."
	assert_process_absent "${container}" '^postgres(\s|$)|postgres -D /data/postgres'
	assert_process_present "${container}" '^redis-server(\s|$)'
}

run_external_redis_url_mode() {
	local redis_container="infisical-aio-ext-redis-url-${RUN_ID}"
	local container="infisical-aio-app-ext-redis-url-${RUN_ID}"
	local config_dir="${WORK_ROOT}/external-redis-url/config"
	local data_dir="${WORK_ROOT}/external-redis-url/data"

	echo "== external redis via REDIS_URL mode =="
	start_external_redis "${redis_container}"
	start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		false \
		false \
		-e "REDIS_URL=redis://${redis_container}:6379/0"
	wait_for_infisical_ready "${container}" "${STARTED_APP_PORT}"

	assert_log_contains "${container}" "External Redis configured. Bundled Redis service staying idle."
	assert_process_present "${container}" '^postgres(\s|$)|postgres -D /data/postgres'
	assert_process_absent "${container}" '^redis-server(\s|$)'
}

run_external_redis_sentinel_mode() {
	local master_container="infisical-aio-ext-redis-sentinel-master-${RUN_ID}"
	local sentinel_container="infisical-aio-ext-redis-sentinel-${RUN_ID}"
	local container="infisical-aio-app-ext-redis-sentinel-${RUN_ID}"
	local config_dir="${WORK_ROOT}/external-redis-sentinel/config"
	local data_dir="${WORK_ROOT}/external-redis-sentinel/data"

	echo "== external redis via Sentinel mode =="
	start_external_redis_sentinel "${master_container}" "${sentinel_container}"
	start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		false \
		false \
		-e "REDIS_SENTINEL_HOSTS=${sentinel_container}:26379" \
		-e "REDIS_SENTINEL_MASTER_NAME=mymaster"
	wait_for_infisical_ready "${container}" "${STARTED_APP_PORT}"

	assert_log_contains "${container}" "External Redis Sentinel/Cluster configured. Bundled Redis service staying idle."
	assert_process_present "${container}" '^postgres(\s|$)|postgres -D /data/postgres'
	assert_process_absent "${container}" '^redis-server(\s|$)'
}

run_external_redis_cluster_mode() {
	local cluster_prefix="infisical-aio-ext-redis-cluster-${RUN_ID}"
	local container="infisical-aio-app-ext-redis-cluster-${RUN_ID}"
	local config_dir="${WORK_ROOT}/external-redis-cluster/config"
	local data_dir="${WORK_ROOT}/external-redis-cluster/data"

	echo "== external redis via Cluster mode =="
	start_external_redis_cluster "${cluster_prefix}"
	start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		false \
		false \
		-e "REDIS_CLUSTER_HOSTS=${cluster_prefix}-1:6379,${cluster_prefix}-2:6379,${cluster_prefix}-3:6379"
	wait_for_infisical_ready "${container}" "${STARTED_APP_PORT}"

	assert_log_contains "${container}" "External Redis Sentinel/Cluster configured. Bundled Redis service staying idle."
	assert_process_present "${container}" '^postgres(\s|$)|postgres -D /data/postgres'
	assert_process_absent "${container}" '^redis-server(\s|$)'
}

run_tls_private_ca_redis_mode() {
	local redis_container="redis-tls-${RUN_ID}"
	local container="infisical-aio-app-redis-tls-${RUN_ID}"
	local config_dir="${WORK_ROOT}/redis-tls/config"
	local data_dir="${WORK_ROOT}/redis-tls/data"
	local cert_dir="${WORK_ROOT}/redis-tls/certs"

	echo "== external redis via rediss + private CA mode =="
	generate_ca_material "${cert_dir}"
	mkdir -p "${config_dir}/aio/certs"
	cp "${cert_dir}/ca.crt" "${config_dir}/aio/certs/ca.crt"
	start_external_redis_tls "${redis_container}" "${cert_dir}"

	start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		false \
		false \
		-e "REDIS_URL=rediss://${redis_container}:6379/0" \
		-e "NODE_EXTRA_CA_CERTS=/config/aio/certs/ca.crt"
	wait_for_infisical_ready "${container}" "${STARTED_APP_PORT}"

	assert_log_contains "${container}" "External Redis configured. Bundled Redis service staying idle."
	assert_process_present "${container}" '^postgres(\s|$)|postgres -D /data/postgres'
	assert_process_absent "${container}" '^redis-server(\s|$)'
}

run_external_smtp_mode() {
	local external_mailpit_container="infisical-aio-ext-mailpit-${RUN_ID}"
	local external_mailpit_port
	local container="infisical-aio-app-ext-smtp-${RUN_ID}"
	local config_dir="${WORK_ROOT}/external-smtp/config"
	local data_dir="${WORK_ROOT}/external-smtp/data"
	local marker_file="${config_dir}/aio/.bootstrap-complete"
	local recovery_email="admin-smtp-${RUN_ID}@example.com"

	echo "== external SMTP via Mailpit mode =="
	start_external_mailpit "${external_mailpit_container}"
	external_mailpit_port="${STARTED_MAILPIT_PORT}"
	start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		false \
		false \
		-e "AIO_BOOTSTRAP_EMAIL=${recovery_email}" \
		-e "AIO_BOOTSTRAP_PASSWORD=InfisicalAio-${RUN_ID}-ExternalSmtp!" \
		-e "AIO_BOOTSTRAP_ORGANIZATION=Infisical AIO SMTP Validation ${RUN_ID}" \
		-e "SMTP_HOST=${external_mailpit_container}" \
		-e "SMTP_PORT=1025" \
		-e "SMTP_IGNORE_TLS=true" \
		-e "SMTP_REQUIRE_TLS=false" \
		-e "SMTP_TLS_REJECT_UNAUTHORIZED=false" \
		-e "SMTP_FROM_ADDRESS=no-reply@infisical.local"
	wait_for_infisical_ready "${container}" "${STARTED_APP_PORT}"

	wait_for_host_file "${marker_file}"
	assert_log_contains "${container}" "External SMTP configured. Bundled Mailpit service staying idle."
	assert_log_contains "${container}" "SMTP - Verified connection to ${external_mailpit_container}:1025"
	assert_process_absent "${container}" '^mailpit(\s|$)'

	curl -fsS \
		-H 'Content-Type: application/json' \
		-d "{\"email\":\"${recovery_email}\"}" \
		-X POST "http://127.0.0.1:${STARTED_APP_PORT}/api/v1/account-recovery/send-email" >/dev/null
	wait_for_mailpit_message "${external_mailpit_port}" "" "" "${recovery_email}" "Infisical account recovery"
}

run_metrics_mode() {
	local container="infisical-aio-metrics-${RUN_ID}"
	local config_dir="${WORK_ROOT}/metrics/config"
	local data_dir="${WORK_ROOT}/metrics/data"
	local metrics_output

	echo "== prometheus metrics mode =="
	start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		false \
		true \
		-e "OTEL_TELEMETRY_COLLECTION_ENABLED=true" \
		-e "OTEL_EXPORT_TYPE=prometheus"
	wait_for_infisical_ready "${container}" "${STARTED_APP_PORT}"
	wait_for_http "http://127.0.0.1:${STARTED_METRICS_PORT}/metrics"

	curl -fsS "http://127.0.0.1:${STARTED_APP_PORT}/api/status" >/dev/null
	metrics_output="$(curl -fsS "http://127.0.0.1:${STARTED_METRICS_PORT}/metrics")"
	[[ ${metrics_output} == *"# HELP"* ]] || fail "Expected Prometheus metrics output to include HELP lines"
	[[ ${metrics_output} == *"infisical_"* ]] || fail "Expected Prometheus metrics output to include Infisical metrics"
}

main() {
	docker info >/dev/null 2>&1 || fail "Docker is not available"
	docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1 || fail "Docker image ${IMAGE_TAG} does not exist. Build it first."
	docker network create "${NETWORK_NAME}" >/dev/null

	case "${MATRIX_MODE}" in
	all)
		run_bundled_mode
		run_manual_secret_override_mode
		run_bootstrap_mode
		run_external_postgres_uri_mode
		run_external_postgres_field_mode
		run_external_redis_url_mode
		run_external_redis_sentinel_mode
		run_external_redis_cluster_mode
		run_tls_private_ca_redis_mode
		run_external_smtp_mode
		run_metrics_mode
		;;
	bundled)
		run_bundled_mode
		;;
	manual-secret-overrides)
		run_manual_secret_override_mode
		;;
	bootstrap)
		run_bootstrap_mode
		;;
	external-postgres-uri)
		run_external_postgres_uri_mode
		;;
	external-postgres-fields)
		run_external_postgres_field_mode
		;;
	external-redis-url)
		run_external_redis_url_mode
		;;
	external-redis-sentinel)
		run_external_redis_sentinel_mode
		;;
	external-redis-cluster)
		run_external_redis_cluster_mode
		;;
	redis-tls-private-ca)
		run_tls_private_ca_redis_mode
		;;
	external-smtp)
		run_external_smtp_mode
		;;
	metrics)
		run_metrics_mode
		;;
	*)
		fail "Unknown runtime matrix mode: ${MATRIX_MODE}"
		;;
	esac

	echo
	echo "Runtime matrix ${MATRIX_MODE} passed for ${IMAGE_TAG}"
}

main "$@"
