# Release Checklist

## Before First Public Push

- replace `assets/app-icon.png` with the real Infisical icon asset
- confirm README, SECURITY, and FUNDING are accurate
- confirm `Support`, `Project`, `TemplateURL`, and `Icon` URLs are correct
- confirm the pinned upstream version and digest match the latest stable Infisical release you intend to ship
- run `python3 scripts/generate_infisical_template.py`
- run `STRICT_PLACEHOLDERS=true bash scripts/validate-derived-repo.sh .`
- run `python3 scripts/validate-template.py`
- build and smoke test the image locally

## Before Enabling Actions

- set `ENABLE_AIO_AUTOMATION=true`
- add `SYNC_TOKEN`
- confirm Renovate is installed for the repo
- verify branch protection and secret scanning are enabled
- confirm `validate-template` passes on PRs before expecting image publish from `main`

## Before Unraid Submission

- install from the XML in a clean Unraid environment
- verify first boot works with bundled PostgreSQL and Redis defaults
- verify external PostgreSQL and Redis overrides work
- verify generated credentials persist across restarts
- confirm GHCR package is public and pullable
- confirm `awesome-unraid` contains the XML and icon
- confirm the README first-run notes match the real install behavior
