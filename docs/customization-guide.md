# Customization Guide

Use this when turning the template into a real app repo.

## First Pass

1. Rename `template-aio.xml` to your final repo slug, for example `myapp-aio.xml`.
2. Replace the placeholder upstream image in [`Dockerfile`](/tmp/unraid-aio-template/Dockerfile).
3. Replace [`assets/app-icon.png`](/tmp/unraid-aio-template/assets/app-icon.png).
4. Update [`README.md`](/tmp/unraid-aio-template/README.md), [`SECURITY.md`](/tmp/unraid-aio-template/SECURITY.md), and [`.github/FUNDING.yml`](/tmp/unraid-aio-template/.github/FUNDING.yml).
5. Replace the starter service command in [`rootfs/etc/services.d/app/run`](/tmp/unraid-aio-template/rootfs/etc/services.d/app/run).
6. Adjust [`scripts/smoke-test.sh`](/tmp/unraid-aio-template/scripts/smoke-test.sh) so it waits for the real ready log line and probes the real HTTP endpoint.
7. Configure [`upstream.toml`](/tmp/unraid-aio-template/upstream.toml) and pin the upstream version in the Dockerfile.
8. Replace the placeholder `<Changes>` block and plan to keep it synced from `CHANGELOG.md` via [`scripts/update-template-changes.py`](/tmp/unraid-aio-template/scripts/update-template-changes.py).

## Files You Will Almost Always Touch

- [`Dockerfile`](/tmp/unraid-aio-template/Dockerfile)
- [`template-aio.xml`](/tmp/unraid-aio-template/template-aio.xml)
- [`README.md`](/tmp/unraid-aio-template/README.md)
- [`scripts/smoke-test.sh`](/tmp/unraid-aio-template/scripts/smoke-test.sh)
- [`scripts/validate-template.py`](/tmp/unraid-aio-template/scripts/validate-template.py)
- [`scripts/update-template-changes.py`](/tmp/unraid-aio-template/scripts/update-template-changes.py)
- [`rootfs/etc/cont-init.d/01-bootstrap.sh`](/tmp/unraid-aio-template/rootfs/etc/cont-init.d/01-bootstrap.sh)
- [`rootfs/etc/services.d/app/run`](/tmp/unraid-aio-template/rootfs/etc/services.d/app/run)
- [`upstream.toml`](/tmp/unraid-aio-template/upstream.toml)

## Internal PostgreSQL

The template includes an optional PostgreSQL example because some AIO repos genuinely need an embedded database.

If the derived app does not need internal PostgreSQL, remove:

- [`rootfs/etc/cont-init.d/02-init-postgres.sh`](/tmp/unraid-aio-template/rootfs/etc/cont-init.d/02-init-postgres.sh)
- [`rootfs/etc/services.d/postgres/run`](/tmp/unraid-aio-template/rootfs/etc/services.d/postgres/run)

If the derived app does need internal PostgreSQL:

- install the required PostgreSQL packages in [`Dockerfile`](/tmp/unraid-aio-template/Dockerfile)
- replace the example init script with real cluster/bootstrap logic
- update the smoke test to validate persistence or first-boot expectations when relevant

## CI and Publishing

The build workflow only publishes when `ENABLE_AIO_AUTOMATION=true`.

Before enabling it:

- run `STRICT_PLACEHOLDERS=true bash scripts/validate-derived-repo.sh .`
- run `python3 scripts/validate-template.py`
- run the smoke test locally against the real image
- set all required repository variables and secrets
- confirm the XML, icon, and package names match the intended public repo
- confirm the upstream monitor matches the real upstream source and stable channel
- confirm `CHANGELOG.md` and the XML `<Changes>` block describe the same latest release

## Trust Signals To Add Before Public Launch

- one screenshot or meaningful demo visual if the app has a UI
- a real first-run section in the README
- an honest limitations or caveats section if the app has rough edges
- a clear `Support` and `Project` URL in the XML
