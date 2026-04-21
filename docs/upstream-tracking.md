# Upstream Tracking

`infisical-aio` tracks the stable upstream `Infisical/infisical` release line and the Docker Hub image digest for `infisical/infisical`.

The bundled beginner-path dependencies are pinned separately:

- internal PostgreSQL stays on major `16`
- internal Redis stays on major `7`

Those majors are intentional because current Infisical requirements documentation says PostgreSQL has been extensively tested with version 16 and Redis should stay on 6.x or 7.x.

## Why

This repo pins both:

- a human-readable upstream version
- the exact immutable image digest

That makes drift explicit and lets the upstream monitor open controlled PRs for both version bumps and digest-only refreshes.

## Config Surface Source Of Truth

The CA template is generated from the pinned upstream `backend/src/lib/config/env.ts`, not from the newest docs page alone.

That is intentional:

- upstream docs can mention knobs that are newer than the pinned image or that come from the broader runtime rather than Infisical's validated env schema
- this wrapper adds a small manual layer for Unraid-relevant extras the app/runtime supports directly, such as `NODE_EXTRA_CA_CERTS` and the optional Prometheus metrics port `9464`
- if docs and runtime disagree, the pinned runtime wins until the upstream image is bumped and re-audited

## Current Pattern

```toml
[upstream]
name = "Infisical"
type = "github-release"
repo = "Infisical/infisical"
image = "infisical/infisical"
version_source = "dockerfile-arg"
version_key = "UPSTREAM_VERSION"
digest_source = "dockerhub-manifest"
digest_key = "UPSTREAM_IMAGE_DIGEST"
strategy = "pr"
stable_only = true
```

## Dockerfile Pinning

```dockerfile
ARG UPSTREAM_VERSION=v0.159.16
ARG UPSTREAM_IMAGE_DIGEST=sha256:...
FROM infisical/infisical:${UPSTREAM_VERSION}@${UPSTREAM_IMAGE_DIGEST}
```

That is the intended pattern for this repo.
