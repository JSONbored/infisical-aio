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
ARG UPSTREAM_VERSION=v0.159.18
ARG UPSTREAM_IMAGE_DIGEST=sha256:...
FROM infisical/infisical:${UPSTREAM_VERSION}@${UPSTREAM_IMAGE_DIGEST}
```

That is the intended pattern for this repo.
