#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${1:-infisical-aio:test}"
READY_LOG="${READY_LOG:-[infisical-aio] Infisical API is ready}"
HTTP_TIMEOUT_SECONDS="${HTTP_TIMEOUT_SECONDS:-300}"
START_TIMEOUT_SECONDS="${START_TIMEOUT_SECONDS:-300}"
POLL_SECONDS="${POLL_SECONDS:-2}"
RUN_ID="${RUN_ID:-$RANDOM}"
NETWORK_NAME="${NETWORK_NAME:-infisical-aio-matrix-${RUN_ID}}"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/infisical-aio-matrix.XXXXXX")"

declare -a CONTAINERS=()

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

assert_file_contains_key() {
	local file="$1"
	local key="$2"
	grep -q "^${key}=" "${file}" || fail "Expected ${file} to contain ${key}"
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

start_infisical() {
	local container="$1"
	local config_dir="$2"
	local data_dir="$3"
	shift 3

	local host_port
	host_port="$(pick_free_port)"
	mkdir -p "${config_dir}" "${data_dir}"

	docker run -d \
		--name "${container}" \
		--network "${NETWORK_NAME}" \
		-p "127.0.0.1:${host_port}:8080" \
		-v "${config_dir}:/config" \
		-v "${data_dir}:/data" \
		-e "SITE_URL=http://127.0.0.1:${host_port}" \
		"$@" \
		"${IMAGE_TAG}" >/dev/null
	register_container "${container}"

	echo "${host_port}"
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

run_bundled_mode() {
	local container="infisical-aio-bundled-${RUN_ID}"
	local config_dir="${WORK_ROOT}/bundled/config"
	local data_dir="${WORK_ROOT}/bundled/data"
	local host_port
	local env_file
	local before_hash
	local after_hash

	echo "== bundled mode =="
	host_port="$(start_infisical "${container}" "${config_dir}" "${data_dir}")"
	wait_for_log "${container}" "${READY_LOG}"
	wait_for_http "http://127.0.0.1:${host_port}/api/status"

	env_file="${config_dir}/aio/generated.env"
	[[ -f ${env_file} ]] || fail "Expected ${env_file} to exist"
	assert_file_contains_key "${env_file}" "ENCRYPTION_KEY"
	assert_file_contains_key "${env_file}" "AUTH_SECRET"
	assert_file_contains_key "${env_file}" "AIO_INTERNAL_DB_PASSWORD"
	assert_file_contains_key "${env_file}" "DB_CONNECTION_URI"
	assert_file_contains_key "${env_file}" "REDIS_URL"
	assert_file_contains_key "${env_file}" "TELEMETRY_ENABLED"

	assert_process_present "${container}" '^postgres(\s|$)|postgres -D /data/postgres'
	assert_process_present "${container}" '^redis-server(\s|$)'

	before_hash="$(shasum -a 256 "${env_file}" | awk '{print $1}')"
	docker restart "${container}" >/dev/null
	wait_for_http "http://127.0.0.1:${host_port}/api/status"
	after_hash="$(shasum -a 256 "${env_file}" | awk '{print $1}')"
	[[ ${before_hash} == "${after_hash}" ]] || fail "Expected ${env_file} to remain unchanged across restart"
}

run_external_postgres_mode() {
	local postgres_container="infisical-aio-ext-postgres-${RUN_ID}"
	local container="infisical-aio-app-ext-postgres-${RUN_ID}"
	local config_dir="${WORK_ROOT}/external-postgres/config"
	local data_dir="${WORK_ROOT}/external-postgres/data"
	local host_port

	echo "== external postgres mode =="
	start_external_postgres "${postgres_container}"
	host_port="$(start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		-e "DB_CONNECTION_URI=postgresql://infisical:infisical@${postgres_container}:5432/infisical")"

	wait_for_log "${container}" "${READY_LOG}"
	wait_for_http "http://127.0.0.1:${host_port}/api/status"

	assert_log_contains "${container}" "External PostgreSQL configured. Bundled PostgreSQL service staying idle."
	assert_process_absent "${container}" '^postgres(\s|$)|postgres -D /data/postgres'
	assert_process_present "${container}" '^redis-server(\s|$)'
}

run_external_redis_mode() {
	local redis_container="infisical-aio-ext-redis-${RUN_ID}"
	local container="infisical-aio-app-ext-redis-${RUN_ID}"
	local config_dir="${WORK_ROOT}/external-redis/config"
	local data_dir="${WORK_ROOT}/external-redis/data"
	local host_port

	echo "== external redis mode =="
	start_external_redis "${redis_container}"
	host_port="$(start_infisical \
		"${container}" \
		"${config_dir}" \
		"${data_dir}" \
		-e "REDIS_URL=redis://${redis_container}:6379/0")"

	wait_for_log "${container}" "${READY_LOG}"
	wait_for_http "http://127.0.0.1:${host_port}/api/status"

	assert_log_contains "${container}" "External Redis configured. Bundled Redis service staying idle."
	assert_process_present "${container}" '^postgres(\s|$)|postgres -D /data/postgres'
	assert_process_absent "${container}" '^redis-server(\s|$)'
}

main() {
	docker info >/dev/null 2>&1 || fail "Docker is not available"
	docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1 || fail "Docker image ${IMAGE_TAG} does not exist. Build it first."
	docker network create "${NETWORK_NAME}" >/dev/null

	run_bundled_mode
	run_external_postgres_mode
	run_external_redis_mode

	echo
	echo "Runtime matrix passed for ${IMAGE_TAG}"
}

main "$@"
