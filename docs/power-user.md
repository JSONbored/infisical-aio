# Power User Notes

`infisical-aio` is meant to boot cleanly with the bundled services first, then let you override pieces only when you actually need to.

If you need the exact Unraid-exposed config list, use `config_surface.toml` plus the generated `docs/configuration-surface.md` reference. That pair is now the repo-native source of truth for the CA template surface.

## Internal vs External Services

Default AIO path:

- PostgreSQL: bundled
- Redis: bundled
- SMTP: bundled Mailpit inbox by default, external optional

External override path:

- set `DB_CONNECTION_URI`, or the upstream `DB_HOST` / `DB_PORT` / `DB_USER` / `DB_PASSWORD` / `DB_NAME` fields, for external PostgreSQL
- set `REDIS_URL`, `REDIS_SENTINEL_HOSTS`, or `REDIS_CLUSTER_HOSTS` for external Redis
- leave `SMTP_HOST` blank for the bundled Mailpit inbox, or set `SMTP_HOST` for an external SMTP server
- set `NODE_EXTRA_CA_CERTS` to a PEM path under `/config` if those external services use a private or self-signed CA

When external PostgreSQL, Redis, or SMTP are configured, the matching bundled service stays idle rather than competing for ports or wasting CPU.

## First-Run Secrets

If left blank, the wrapper generates and persists:

- `ENCRYPTION_KEY`
- `AUTH_SECRET`
- `AIO_MAILPIT_UI_USERNAME`
- `AIO_MAILPIT_UI_PASSWORD`

Those values are stored under `/config/aio/generated.env`. Back them up. If you lose them while keeping the database, you will have a broken deployment.

## Bootstrap Automation

Optional bootstrap fields:

- `AIO_BOOTSTRAP_EMAIL`
- `AIO_BOOTSTRAP_PASSWORD`
- `AIO_BOOTSTRAP_ORGANIZATION`
- `AIO_BOOTSTRAP_SAVE_RESPONSE`

Bundled inbox controls:

- `AIO_ENABLE_BUNDLED_MAILPIT`
- `AIO_MAILPIT_UI_USERNAME`
- `AIO_MAILPIT_UI_PASSWORD`

The bootstrap flow only makes sense on a fresh instance. After that, the wrapper marks bootstrap as complete.

## High-Impact Advanced Areas

- SMTP: the bundled Mailpit inbox is suitable for local or lab invites, resets, and email-dependent auth flows; real delivery still requires external SMTP
- SSO/Auth: GitHub, GitLab, Google, and SAML/OIDC-related settings
- Audit Logs: PostgreSQL audit storage toggles and optional ClickHouse sink
- Telemetry: OTEL, DataDog, and self-host telemetry toggles
- Prometheus metrics: if you set `OTEL_TELEMETRY_COLLECTION_ENABLED=true` and `OTEL_EXPORT_TYPE=prometheus`, also publish host port `9464`
- Secret Scanning and App Connections: large advanced surface, mostly for power users and enterprise-like setups
- Gateway/PAM/HSM: real advanced operators only
