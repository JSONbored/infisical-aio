#!/command/with-contenv bash
# shellcheck shell=bash
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
