# infisical-aio

`infisical-aio` packages [Infisical](https://github.com/Infisical/infisical) for an Unraid-first, single-container install path. The image wraps the official `infisical/infisical` container and bundles the required PostgreSQL and Redis services by default so a beginner install can stay small instead of turning into a separate stack immediately.

This is still a real secrets-management platform, not a toy appliance. The AIO wrapper simplifies first boot, but it does not remove the need to think about backups, the correctness of `SITE_URL`, SMTP if you want mail-backed features, and whether you actually want an embedded database/cache long term.

## What This Repo Does

- pins the official Infisical image by upstream tag and digest
- bundles internal PostgreSQL and Redis for the default Unraid path
- allows external PostgreSQL and Redis overrides from the CA template
- auto-generates and persists required first-run secrets when you leave them blank
- optionally bootstraps the first admin account and organization through the documented Infisical bootstrap API
- exposes a wide CA template surface for power users while keeping the beginner path small

## Beginner Install

1. Install the Unraid template.
2. Leave the default `/config` and `/data` paths in place unless you have a reason to move them.
3. Set `SITE_URL` to the real URL users will visit, such as `https://secrets.example.com` or `http://tower.local:8080`.
4. Start the container and wait for the API to come up.
5. Create the first account in the UI, or set the optional `AIO_BOOTSTRAP_*` fields in Advanced View to auto-bootstrap it.

By default, the wrapper will:

- generate and persist `ENCRYPTION_KEY` and `AUTH_SECRET`
- create and use an internal PostgreSQL database
- create and use an internal Redis instance
- disable product telemetry by default

## Advanced Overrides

Advanced View is where the power-user surface lives:

- external `DB_CONNECTION_URI` or separate DB fields
- external Redis URL, Sentinel, or Cluster settings
- SMTP and custom CA settings
- SSO and integration client credentials
- audit log storage, ClickHouse, telemetry, and DataDog toggles
- secret scanning, gateway, PAM, HSM, and app connection settings
- optional headless bootstrap fields for the first admin/org

## Important Tradeoffs

- The default AIO path embeds PostgreSQL and Redis in one container for convenience, not because that is the ideal long-term production topology.
- Infisical itself recommends external high-availability PostgreSQL and Redis for more serious production deployments.
- `SITE_URL` matters. If you set it wrong, browser flows, links, email behavior, and some integrations will break in subtle ways.
- If you enable automatic bootstrap, you are creating a highly privileged instance-admin identity during first boot. Treat those credentials carefully.

## Local Validation

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

## Upstream Tracking

`upstream.toml` tracks stable upstream releases from `Infisical/infisical` and the Docker Hub image digest for the wrapped container image.
