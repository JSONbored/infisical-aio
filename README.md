# infisical-aio

An Unraid-first, single-container deployment of [Infisical](https://github.com/Infisical/infisical) for people who want the easiest reliable self-hosted install without manually wiring PostgreSQL and Redis on day one.

`infisical-aio` is opinionated for a predictable beginner install, but it does not hide the real tradeoffs: this is still a serious secrets-management platform, `SITE_URL` still needs to be correct, backups still matter, and the bundled database/cache path is convenience infrastructure rather than the ideal long-term production topology.

## What This Image Includes

- Infisical web UI and API on port `8080`
- Embedded PostgreSQL 16 for the default beginner path
- Embedded Redis 7 for the default beginner path
- Persistent `/config` storage for generated wrapper state and bootstrap artifacts
- Persistent `/data` storage for bundled PostgreSQL and Redis state
- Automatic generation and persistence of `ENCRYPTION_KEY` and `AUTH_SECRET` when you leave them blank
- Optional first-run bootstrap flow for the initial admin account and organization
- Unraid CA template at [infisical-aio.xml](infisical-aio.xml)

## Beginner Install

If you want the simplest supported path:

1. Install the Unraid template.
2. Leave the default `/config` and `/data` paths in place unless you have a reason to move them.
3. Set `SITE_URL` to the real URL users will visit, such as `https://secrets.example.com` or `http://tower.local:8080`.
4. Start the container and wait for the API to come up.
5. Create the first account in the UI, or set the optional `AIO_BOOTSTRAP_*` fields in Advanced View to auto-bootstrap it.

If you leave the important secrets blank, the wrapper will:

- generate and persist `ENCRYPTION_KEY`
- generate and persist `AUTH_SECRET`
- create and use an internal PostgreSQL database
- create and use an internal Redis instance
- disable product telemetry by default

## Power User Surface

This repo is deliberately not a stripped-down wrapper. Advanced View exposes the broader practical Infisical self-hosted environment surface plus the AIO defaults for the bundled PostgreSQL + Redis path. In Advanced View you can:

- point Infisical at external PostgreSQL with `DB_CONNECTION_URI` or the upstream DB fields
- point Infisical at external Redis, Redis Sentinel, or Redis Cluster instead of the bundled instance
- configure SMTP for invites, password resets, and mail-backed auth flows
- expose the wider upstream SSO, audit log, telemetry, secret scanning, gateway, PAM, HSM, and app-connection settings
- keep the bundled internal defaults for the easiest install while still retaining the normal escape hatches when you need them

The wrapper still defaults to the internal bundled services so new Unraid users are not forced into extra containers on day one.

## Runtime Notes

- The bundled internal services are pinned to PostgreSQL 16 and Redis 7.x because those are within Infisical's currently documented support range.
- The default AIO path embeds PostgreSQL and Redis for convenience. For more serious production deployments, Infisical recommends external high-availability PostgreSQL and Redis.
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

Local validation in this repo is built around:

- XML validation for the audited template surface
- shell and Python syntax checks
- local Docker build and smoke coverage
- restart and persistence checks for the embedded Infisical stack

Run the source-repo-first checks before enabling automation:

```bash
STRICT_PLACEHOLDERS=true bash scripts/validate-derived-repo.sh .
python3 scripts/validate-template.py
python3 scripts/generate_infisical_template.py --check
docker build -t infisical-aio:test .
bash scripts/smoke-test.sh infisical-aio:test
```

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
