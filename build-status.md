# Build Status

This repo is a template starter.

Before enabling automation for a derived repo:

- replace all placeholder values
- run `STRICT_PLACEHOLDERS=true bash scripts/validate-derived-repo.sh .`
- verify the smoke test matches the actual container behavior
- set `ENABLE_AIO_AUTOMATION=true` and add `SYNC_TOKEN`
- install Renovate for ongoing updates
- configure upstream monitoring
- confirm GHCR package visibility after first publish
