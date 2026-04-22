# infisical-aio

![infisical-aio](https://socialify.git.ci/JSONbored/infisical-aio/image?custom_description=Unraid+CA+AIO+template+and+Docker+image+for+Infisical%2C+a+self-hosted+secrets+manager+with+bundled+PostgreSQL%2C+Redis%2C+and+Mailpit+for+the+easiest+first+boot.&custom_language=Dockerfile&description=1&font=Raleway&forks=1&issues=1&language=1&logo=https%3A%2F%2Fraw.githubusercontent.com%2FJSONbored%2Finfisical-aio%2Fmain%2Fassets%2Fapp-icon.png&name=1&owner=1&pattern=Formal+Invitation&pulls=1&stargazers=1&theme=Light)

An Unraid-first, single-container deployment of [Infisical](https://github.com/Infisical/infisical) for people who want the easiest reliable self-hosted install without manually wiring PostgreSQL and Redis on day one.

`infisical-aio` is opinionated for a predictable beginner install, but it does not hide the real tradeoffs: this is still a serious secrets-management platform, `SITE_URL` still needs to be correct, backups still matter, and the bundled database/cache path is convenience infrastructure rather than the ideal long-term production topology.

## What This Image Includes

- Infisical web UI and API on port `8080`
- Embedded PostgreSQL 16 for the default beginner path
- Embedded Redis 7 for the default beginner path
- Embedded Mailpit inbox for local or lab SMTP capture on the default beginner path
- Persistent `/config` storage for generated wrapper state and bootstrap artifacts
- Persistent `/data` storage for bundled PostgreSQL and Redis state
- Automatic generation and persistence of `ENCRYPTION_KEY` and `AUTH_SECRET` when you leave them blank
- Automatic generation and persistence of bundled Mailpit UI credentials when you leave them blank
- Optional first-run bootstrap flow for the initial admin account and organization
- Unraid CA template at [infisical-aio.xml](infisical-aio.xml)

## Beginner Install

If you want the simplest supported path:

1. Install the Unraid template.
2. Leave the default `/config` and `/data` paths in place unless you have a reason to move them.
3. Set `SITE_URL` to the real URL users will visit, such as `https://secrets.example.com` or `http://tower.local:8080`.
4. Start the container and wait for the API to come up.
5. If you want to inspect local mail, open the bundled Mailpit inbox on port `8025` and read the generated `AIO_MAILPIT_UI_USERNAME` / `AIO_MAILPIT_UI_PASSWORD` values from `/config/aio/generated.env`.
6. Create the first account in the UI, or set the optional `AIO_BOOTSTRAP_*` fields in Advanced View to auto-bootstrap it.

If you leave the important secrets blank, the wrapper will:

- generate and persist `ENCRYPTION_KEY`
- generate and persist `AUTH_SECRET`
- create and use an internal PostgreSQL database
- create and use an internal Redis instance
- create and use a bundled local Mailpit inbox unless you configure external SMTP
- disable product telemetry by default

## Power User Surface

This repo is deliberately not a stripped-down wrapper. Advanced View exposes the broader practical Infisical self-hosted environment surface plus the AIO defaults for the bundled PostgreSQL + Redis path. In Advanced View you can:

- point Infisical at external PostgreSQL with `DB_CONNECTION_URI` or the upstream DB fields
- point Infisical at external Redis, Redis Sentinel, or Redis Cluster instead of the bundled instance
- use the bundled Mailpit inbox for local or lab email-dependent flows, or configure external SMTP for real delivery
- expose the wider upstream SSO, audit log, telemetry, secret scanning, gateway, PAM, HSM, and app-connection settings
- keep the bundled internal defaults for the easiest install while still retaining the normal escape hatches when you need them

The wrapper still defaults to the internal bundled services so new Unraid users are not forced into extra containers on day one.

The canonical exposed configuration manifest now lives in [config_surface.toml](config_surface.toml). The generated operator-facing reference is [docs/configuration-surface.md](docs/configuration-surface.md), and the CA template XML is rendered from the same source.

Additional advanced wrapper-specific knobs worth knowing about:

- `AIO_ENABLE_BUNDLED_MAILPIT` to keep or disable the bundled local inbox when `SMTP_HOST` is blank
- `AIO_MAILPIT_UI_USERNAME` and `AIO_MAILPIT_UI_PASSWORD` if you want to override the generated inbox UI credentials
- `NODE_EXTRA_CA_CERTS` if your external Redis or other upstream dependency uses a private or self-signed CA; point it at a PEM file under `/config`, such as `/config/aio/certs/custom-ca.pem`
- optional host port `9464` when you enable `OTEL_TELEMETRY_COLLECTION_ENABLED=true` with `OTEL_EXPORT_TYPE=prometheus`

## Runtime Notes

- The bundled internal services are pinned to PostgreSQL 16 and Redis 7.x because those are within Infisical's currently documented support range.
- The bundled local inbox is Mailpit, running with UI auth enabled, SMTP kept internal to the container, remote CSS/fonts blocked, version checks disabled, and SQLite WAL disabled for Unraid-friendly persistence.
- The default AIO path embeds PostgreSQL and Redis for convenience. For more serious production deployments, Infisical recommends external high-availability PostgreSQL and Redis.
- The bundled Mailpit inbox is for local or lab use. It helps first boot and local mail-dependent flows, but it is not a production mail relay and should not be mistaken for real deliverability infrastructure.
- `SITE_URL` matters. If you set it wrong, browser flows, links, email behavior, and some integrations will break in subtle ways.
- If you enable automatic bootstrap, you are creating a highly privileged instance-admin identity during first boot. Treat those credentials carefully.
- If you plan to expose this publicly, treat your reverse proxy, SMTP, app credentials, and backup strategy as part of the deployment rather than optional cleanup.

## Publishing and Releases

- Wrapper releases use the upstream version plus an AIO revision, such as `v0.159.16-aio.1`.
- The repo monitors upstream releases through [upstream.toml](upstream.toml) and [scripts/check-upstream.py](scripts/check-upstream.py).
- Release notes are generated with `git-cliff`.
- The Unraid template `<Changes>` block is synced from `CHANGELOG.md` during release preparation.
- `main` publishes `latest`, the pinned upstream version tag, the explicit AIO package tag, and `sha-<commit>` to GHCR.
- When Docker Hub credentials are configured, the same publish flow pushes matching tags to Docker Hub in parallel.

See [docs/releases.md](docs/releases.md) for the release workflow details.

## Validation

Required local validation is pytest-first:

```bash
python3 -m venv .venv-local
.venv-local/bin/pip install -r requirements-dev.txt
.venv-local/bin/pytest tests/unit tests/template --junit-xml=reports/pytest-unit.xml -o junit_family=xunit1
.venv-local/bin/pytest tests/integration -m integration --junit-xml=reports/pytest-integration.xml -o junit_family=xunit1
trunk flakytests validate --junit-paths "reports/pytest-unit.xml,reports/pytest-integration.xml"
trunk check --show-existing --all
```

The extended runtime matrix now lives behind an opt-in pytest marker so the deeper bundled-vs-external coverage still runs through the shared suite:

```bash
python3 scripts/validate_config_surface.py
python3 scripts/generate_infisical_template.py --check
python3 scripts/generate_config_surface_docs.py --check
INFISICAL_ENABLE_RUNTIME_MATRIX=1 \
.venv-local/bin/pytest tests/integration/test_runtime_matrix.py -m extended_integration
```

That manual proof helper covers:

- bundled PostgreSQL + Redis boot cleanly
- bundled Mailpit boots cleanly, requires UI auth, and verifies successfully as Infisical's default local SMTP target
- manual `ENCRYPTION_KEY` and `AUTH_SECRET` overrides are honored without being rewritten into `/config/aio/generated.env`
- automatic `AIO_BOOTSTRAP_*` bootstrap completes, can persist the saved response artifact, and can drive a real account-recovery email into bundled Mailpit
- `/config/aio/generated.env` persists unchanged across restart
- external PostgreSQL keeps the bundled PostgreSQL service idle for both `DB_CONNECTION_URI` and upstream `DB_HOST`/`DB_PORT`/`DB_USER`/`DB_PASSWORD`/`DB_NAME`
- external Redis keeps the bundled Redis service idle for `REDIS_URL`, Redis Sentinel, and Redis Cluster
- external SMTP can be validated against an external Mailpit container while the bundled Mailpit service stays idle
- private-CA `rediss://` works when `NODE_EXTRA_CA_CERTS` points at a mounted PEM bundle
- Prometheus metrics are exposed on `/metrics` when `OTEL_TELEMETRY_COLLECTION_ENABLED=true` and `OTEL_EXPORT_TYPE=prometheus`

Still manual:

- reverse proxy, TLS, and secure-cookie behavior for your real `SITE_URL`
- real SMTP delivery, SMTP custom-CA mail flows, and provider-specific deliverability behavior
- external PostgreSQL TLS/root-cert validation
- Redis Sentinel/Cluster auth and TLS combinations beyond the locally validated no-auth path
- SSO/provider-specific integrations and enterprise feature integrations
- Unraid UI behavior in the CA template editor itself

## Community Apps Sync

This repo is the source repo. The CA-facing XML and icon should be synced into `JSONbored/awesome-unraid` only after:

1. local validation passes
2. the image is publishable
3. the support thread content is ready

## Support

- Repo issues: [JSONbored/infisical-aio issues](https://github.com/JSONbored/infisical-aio/issues)
- Upstream app: [Infisical/infisical](https://github.com/Infisical/infisical)
- Official docs: [infisical.com/docs](https://infisical.com/docs)

## Funding

If this work saves you time, support it here:

- [GitHub Sponsors](https://github.com/sponsors/JSONbored)
- [Ko-fi](https://ko-fi.com/jsonbored)
- [Buy Me a Coffee](https://buymeacoffee.com/jsonbored)

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=JSONbored/infisical-aio&theme=dark)](https://star-history.com/#JSONbored/infisical-aio&Date)
