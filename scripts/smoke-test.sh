#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${1:-infisical-aio:test}"
CONTAINER_NAME="${CONTAINER_NAME:-infisical-aio-smoke}"
HOST_PORT="${HOST_PORT:-18080}"
CONTAINER_PORT="${CONTAINER_PORT:-8080}"
READY_LOG="${READY_LOG:-[infisical-aio] Infisical API is ready}"
SMTP_READY_LOG="${SMTP_READY_LOG:-SMTP - Verified connection to 127.0.0.1:1025}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://127.0.0.1:${HOST_PORT}/api/status}"
READY_TIMEOUT_SECONDS="${READY_TIMEOUT_SECONDS:-300}"
HTTP_TIMEOUT_SECONDS="${HTTP_TIMEOUT_SECONDS:-60}"

cleanup() {
	docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

docker run -d \
	--name "${CONTAINER_NAME}" \
	-p "${HOST_PORT}:${CONTAINER_PORT}" \
	-e SITE_URL="http://127.0.0.1:${HOST_PORT}" \
	"${IMAGE_TAG}" >/dev/null

ready_deadline=$((SECONDS + READY_TIMEOUT_SECONDS))
while ((SECONDS < ready_deadline)); do
	CURRENT_LOGS="$(docker logs "${CONTAINER_NAME}" 2>&1 || true)"
	if [[ ${CURRENT_LOGS} == *"${READY_LOG}"* ]]; then
		break
	fi
	if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
		echo "Smoke test container exited unexpectedly." >&2
		docker logs "${CONTAINER_NAME}" >&2 || true
		exit 1
	fi
	sleep 2
done

if [[ -n ${READY_LOG} ]]; then
	CURRENT_LOGS="$(docker logs "${CONTAINER_NAME}" 2>&1 || true)"
	[[ ${CURRENT_LOGS} == *"${READY_LOG}"* ]]
fi

if [[ -n ${SMTP_READY_LOG} ]]; then
	smtp_deadline=$((SECONDS + HTTP_TIMEOUT_SECONDS))
	while ((SECONDS < smtp_deadline)); do
		CURRENT_LOGS="$(docker logs "${CONTAINER_NAME}" 2>&1 || true)"
		if [[ ${CURRENT_LOGS} == *"${SMTP_READY_LOG}"* ]]; then
			break
		fi
		sleep 2
	done

	CURRENT_LOGS="$(docker logs "${CONTAINER_NAME}" 2>&1 || true)"
	[[ ${CURRENT_LOGS} == *"${SMTP_READY_LOG}"* ]]
fi

http_deadline=$((SECONDS + HTTP_TIMEOUT_SECONDS))
while ((SECONDS < http_deadline)); do
	if curl -fsS "${HEALTHCHECK_URL}" >/dev/null 2>&1; then
		break
	fi
	sleep 2
done

curl -fsS "${HEALTHCHECK_URL}" >/dev/null
