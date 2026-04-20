# Unraid AIO Template

A hardened starter for future `*-aio` repositories: one public repo per app, one companion GHCR image, one Unraid CA XML, and one beginner-first experience that still leaves room for power-user overrides.

This template is opinionated on purpose. It is built for repos that should be:

- easy for newcomers to install
- honest about what is embedded versus external
- reproducible in CI before publishing `latest`
- cleanly syncable into `awesome-unraid`

## What This Template Ships With

- starter [`Dockerfile`](/tmp/unraid-aio-template/Dockerfile) for wrapping an upstream image with `s6-overlay`
- starter CA XML at [`template-aio.xml`](/tmp/unraid-aio-template/template-aio.xml)
- reusable smoke test at [`scripts/smoke-test.sh`](/tmp/unraid-aio-template/scripts/smoke-test.sh)
- generic XML validator at [`scripts/validate-template.py`](/tmp/unraid-aio-template/scripts/validate-template.py)
- CI gate helper and tests at [`scripts/ci_flags.py`](/tmp/unraid-aio-template/scripts/ci_flags.py) and [`scripts/test-ci-flags.py`](/tmp/unraid-aio-template/scripts/test-ci-flags.py)
- changelog-to-XML sync helper at [`scripts/update-template-changes.py`](/tmp/unraid-aio-template/scripts/update-template-changes.py)
- derived-repo guardrail script at [`scripts/validate-derived-repo.sh`](/tmp/unraid-aio-template/scripts/validate-derived-repo.sh)
- upstream monitor scaffold at [`upstream.toml`](/tmp/unraid-aio-template/upstream.toml)
- GitHub Actions for validation, manual heavy-job gating, main-branch smoke-test/publish, security checks, and optional `awesome-unraid` sync
- starter docs, changelog, funding, issue templates, and security policy
- public repo checklists under [`docs/`](/tmp/unraid-aio-template/docs)

## Design Principles

- single-container first when it is realistic and not misleading
- safe defaults for beginners, advanced knobs for power users
- generated first-run secrets only when the app truly needs them
- no publish until placeholders are gone and smoke tests pass
- pinned workflow action SHAs and Renovate-managed dependency updates
- stable-only upstream tracking with PR-first updates
- optional upstream image digest tracking for repos that pin immutable manifests
- update automation opens PRs, but merge decisions stay manual
- public repos stay public-facing and product-facing only

## Recommended Workflow

1. Create a new private repo from this template.
2. Rename `template-aio.xml` to the final app slug, for example `myapp-aio.xml`.
3. Replace placeholders in the Dockerfile, XML, rootfs scripts, smoke test, README, funding file, and security policy.
4. Replace [`assets/app-icon.png`](/tmp/unraid-aio-template/assets/app-icon.png) with the real icon.
5. Follow [`docs/customization-guide.md`](/tmp/unraid-aio-template/docs/customization-guide.md).
6. Follow [`docs/repo-settings.md`](/tmp/unraid-aio-template/docs/repo-settings.md).
7. Keep `ENABLE_AIO_AUTOMATION` unset until the derived repo passes local validation.
8. When ready, set `ENABLE_AIO_AUTOMATION=true` and let CI publish and sync.
9. Install the Renovate GitHub App for the derived repo so pinned actions and Docker dependencies stay current.
10. Configure [`upstream.toml`](/tmp/unraid-aio-template/upstream.toml) so the repo can monitor the wrapped upstream app.
11. Replace the placeholder `<Changes>` block and then let release automation keep it in sync from `CHANGELOG.md`.

## Required Actions Variables

Only one Actions variable is required for the default JSONbored workflow:

- `ENABLE_AIO_AUTOMATION=true`

Optional overrides:

- `IMAGE_NAME_OVERRIDE=jsonbored/yourapp-aio`
- `TEMPLATE_XML=yourapp-aio.xml`
- `AWESOME_UNRAID_REPOSITORY=JSONbored/awesome-unraid`
- `AWESOME_UNRAID_XML_NAME=yourapp-aio.xml`
- `AWESOME_UNRAID_ICON_NAME=yourapp.png`
- `TEMPLATE_ICON_PATH=assets/app-icon.png`

If you do not set the optional sync overrides, the workflow defaults to:

- target repo: `JSONbored/awesome-unraid`
- XML name: `<repo-name>.xml`
- icon path: `assets/app-icon.png`
- icon name: derived from the XML name, for example `yourapp-aio.xml -> yourapp.png`

## Required Actions Secret

- `SYNC_TOKEN`
  - fine-grained PAT
  - repository access: `JSONbored/awesome-unraid`
  - permission: `Contents: Read and write`

## Files To Customize First

- [`Dockerfile`](/tmp/unraid-aio-template/Dockerfile)
- [`template-aio.xml`](/tmp/unraid-aio-template/template-aio.xml)
- [`scripts/smoke-test.sh`](/tmp/unraid-aio-template/scripts/smoke-test.sh)
- [`scripts/validate-template.py`](/tmp/unraid-aio-template/scripts/validate-template.py)
- [`scripts/update-template-changes.py`](/tmp/unraid-aio-template/scripts/update-template-changes.py)
- [`rootfs/etc/cont-init.d/01-bootstrap.sh`](/tmp/unraid-aio-template/rootfs/etc/cont-init.d/01-bootstrap.sh)
- [`rootfs/etc/services.d/app/run`](/tmp/unraid-aio-template/rootfs/etc/services.d/app/run)
- [`README.md`](/tmp/unraid-aio-template/README.md)
- [`.github/FUNDING.yml`](/tmp/unraid-aio-template/.github/FUNDING.yml)
- [`SECURITY.md`](/tmp/unraid-aio-template/SECURITY.md)
- [`upstream.toml`](/tmp/unraid-aio-template/upstream.toml)

## Validation Flow

Derived repos created from this template should follow this order:

1. local placeholder cleanup
2. `STRICT_PLACEHOLDERS=true bash scripts/validate-derived-repo.sh .`
3. `python3 scripts/validate-template.py`
4. local image build
5. local smoke test
6. enable automation
7. CI validation and publish
8. `awesome-unraid` sync using the repo-name-derived defaults or your optional overrides
9. real Unraid install validation

Use [`docs/release-checklist.md`](/tmp/unraid-aio-template/docs/release-checklist.md) before making a derived repo public or submitting it to CA.

## Upstream Tracking

Use [`docs/upstream-tracking.md`](/tmp/unraid-aio-template/docs/upstream-tracking.md) to wire the derived repo to the stable upstream app it wraps.

## Releases

This template should use normal semver releases such as `v0.1.0`, not upstream-aligned app versions.

See [`docs/releases.md`](/tmp/unraid-aio-template/docs/releases.md) for the protected-branch-safe release workflow and changelog process.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=JSONbored/unraid-aio-template&type=date&legend=top-left)](https://www.star-history.com/#JSONbored/unraid-aio-template&Date)
