#!/command/with-contenv bash
set -euo pipefail

mkdir -p /config/aio

ENV_FILE="/config/aio/generated.env"
touch "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

persist_if_missing() {
    local key="$1"
    local value="$2"
    if ! grep -q "^${key}=" "${ENV_FILE}"; then
        printf '%s="%s"\n' "${key}" "${value}" >> "${ENV_FILE}"
    fi
}

# Replace these with any first-run secrets your app needs.
if [ -z "${APP_SECRET_KEY:-}" ]; then
    persist_if_missing "APP_SECRET_KEY" "$(openssl rand -hex 64)"
fi

echo "[aio-template] Generated first-run values are stored at ${ENV_FILE}."
