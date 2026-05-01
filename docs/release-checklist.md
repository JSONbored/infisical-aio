# Release Checklist

## Before First Public Push

- replace `assets/app-icon.png` with the real Infisical icon asset
- confirm README, SECURITY, and FUNDING are accurate
- confirm `Support`, `Project`, `TemplateURL`, and `Icon` URLs are correct
- confirm the pinned upstream version and digest match the latest stable Infisical release you intend to ship
- run `python3 scripts/generate_infisical_template.py`
- run `pytest tests/unit tests/template --junit-xml=reports/pytest-unit.xml -o junit_family=xunit1` locally
- run `pytest tests/integration -m integration --junit-xml=reports/pytest-integration.xml -o junit_family=xunit1` locally
- from `aio-fleet`, run `python -m aio_fleet validate --repo infisical-aio`
- from `aio-fleet`, run `python -m aio_fleet control-check --repo infisical-aio --sha <sha> --event pull_request`
- optionally run `INFISICAL_ENABLE_RUNTIME_MATRIX=1 pytest tests/integration/test_runtime_matrix.py -m extended_integration` for deeper bundled-vs-external proof

## Before Enabling Actions

- confirm the `aio-fleet` GitHub App is installed on this repo and `awesome-unraid`
- confirm shared dependency/upstream automation is represented in `aio-fleet`
- verify branch protection and secret scanning are enabled
- confirm `aio-fleet / required` passes before expecting central publish from `main`

## Before Unraid Submission

- install from the XML in a clean Unraid environment
- verify first boot works with bundled PostgreSQL and Redis defaults
- verify external PostgreSQL and Redis overrides work
- verify generated credentials persist across restarts
- confirm the Docker Hub image is public and pullable
- confirm `awesome-unraid` contains the XML and icon
- confirm the README first-run notes match the real install behavior
