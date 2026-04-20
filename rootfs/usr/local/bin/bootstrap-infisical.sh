#!/command/with-contenv bash
# shellcheck shell=bash
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/env-helpers.sh

load_generated_env

PORT_VALUE="${PORT:-8080}"
STATUS_URL="http://127.0.0.1:${PORT_VALUE}/api/status"
BOOTSTRAP_URL="http://127.0.0.1:${PORT_VALUE}/api/v1/admin/bootstrap"
BOOTSTRAP_MARKER="/config/aio/.bootstrap-complete"
BOOTSTRAP_RESPONSE="/config/aio/bootstrap-response.json"
SAVE_RESPONSE="${AIO_BOOTSTRAP_SAVE_RESPONSE:-false}"

deadline=$((SECONDS + 300))
until curl -fsS "${STATUS_URL}" >/dev/null 2>&1; do
	if ((SECONDS >= deadline)); then
		echo "[infisical-aio] Timed out waiting for the Infisical API."
		exit 1
	fi
	sleep 2
done

echo "[infisical-aio] Infisical API is ready"

if [[ -f ${BOOTSTRAP_MARKER} ]]; then
	exit 0
fi

if [[ -z ${AIO_BOOTSTRAP_EMAIL-} ]] || [[ -z ${AIO_BOOTSTRAP_PASSWORD-} ]] || [[ -z ${AIO_BOOTSTRAP_ORGANIZATION-} ]]; then
	exit 0
fi

tmp_response="$(mktemp)"
request_body="$(jq -cn \
	--arg email "${AIO_BOOTSTRAP_EMAIL}" \
	--arg password "${AIO_BOOTSTRAP_PASSWORD}" \
	--arg organization "${AIO_BOOTSTRAP_ORGANIZATION}" \
	'{email: $email, password: $password, organization: $organization}')"
http_code="$(curl -sS -o "${tmp_response}" -w '%{http_code}' \
	-H 'Content-Type: application/json' \
	-d "${request_body}" \
	-X POST "${BOOTSTRAP_URL}")"

if [[ ${http_code} == "200" ]]; then
	echo "[infisical-aio] Instance bootstrap completed."
	touch "${BOOTSTRAP_MARKER}"
	chmod 600 "${BOOTSTRAP_MARKER}"
	if [[ ${SAVE_RESPONSE} == "true" ]]; then
		install -m 600 "${tmp_response}" "${BOOTSTRAP_RESPONSE}"
		echo "[infisical-aio] Saved bootstrap response to ${BOOTSTRAP_RESPONSE}. Treat it as a root credential."
	fi
	rm -f "${tmp_response}"
	exit 0
fi

if grep -qi "already bootstrapped" "${tmp_response}"; then
	echo "[infisical-aio] Instance was already bootstrapped. Marking bootstrap as complete."
	touch "${BOOTSTRAP_MARKER}"
	chmod 600 "${BOOTSTRAP_MARKER}"
	rm -f "${tmp_response}"
	exit 0
fi

echo "[infisical-aio] Bootstrap request failed with HTTP ${http_code}."
cat "${tmp_response}" >&2 || true
rm -f "${tmp_response}"
exit 1
