# Infisical AIO Architecture

`infisical-aio` is intentionally opinionated:

- the default path is one container
- PostgreSQL 16 and Redis 7.x are bundled by default
- external PostgreSQL and Redis remain available as advanced overrides
- required first-run secrets are generated and persisted automatically if you leave them blank

## Runtime Layout

- `/config`
  - generated wrapper state
  - persisted first-run secrets
  - optional bootstrap artifacts
- `/data/postgres`
  - bundled PostgreSQL data directory
- `/data/redis`
  - bundled Redis persistence

## Wrapper Rules

- `HOST` is forced to `0.0.0.0` for container accessibility.
- `PORT` stays aligned with the container port exposed by the CA template.
- user-supplied environment variables win over generated defaults
- bundled PostgreSQL and Redis stay idle when you point the app at external services
- the bundled services intentionally stay within Infisical's current support guidance instead of following Debian's newest majors automatically

## Advanced Wrapper Extras

- `NODE_EXTRA_CA_CERTS` is exposed for private or self-signed CA bundles used by external Redis or other outbound TLS clients. Put the PEM file somewhere under `/config`, such as `/config/aio/certs/custom-ca.pem`.
- Prometheus pull-mode metrics are supported by the upstream app on port `9464`, but the CA template leaves that host port blank by default. Only publish it when you intentionally enable `OTEL_TELEMETRY_COLLECTION_ENABLED=true` and `OTEL_EXPORT_TYPE=prometheus`.

## Bootstrap Behavior

The wrapper supports two valid first-boot paths:

1. manual UI bootstrap
2. automatic bootstrap via `AIO_BOOTSTRAP_EMAIL`, `AIO_BOOTSTRAP_PASSWORD`, and `AIO_BOOTSTRAP_ORGANIZATION`

Automatic bootstrap is convenient, but it creates a highly privileged machine identity token. Treat any saved bootstrap response as a root credential.
