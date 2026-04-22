# Upstream Tracking

`infisical-aio` tracks the stable upstream `Infisical/infisical` release line and the Docker Hub image digest for `infisical/infisical`.

The bundled beginner-path dependencies are pinned separately:

- internal PostgreSQL stays on major `16`
- internal Redis stays on major `7`
- bundled Mailpit is pinned to an explicit upstream release and digest rather than floating `latest`

Those majors are intentional because current Infisical requirements documentation says PostgreSQL has been extensively tested with version 16 and Redis should stay on 6.x or 7.x.

## Why

This repo pins both:

- a human-readable upstream version
- the exact immutable image digest

That makes drift explicit and lets the upstream monitor open controlled PRs for both version bumps and digest-only refreshes.

## Config Surface Source Of Truth

The repo-native source of truth is `config_surface.toml`, not the generated XML and not the newest docs page alone.

That is intentional:

- the manifest explicitly models every exposed config item, including repo-specific Unraid controls, requiredness, runtime mode, and help text
- upstream-backed entries are validated against the pinned `backend/src/lib/config/env.ts`
- runtime shell parsing and first-boot defaults are validated against that same manifest so drift fails fast
- the CA template XML and generated markdown reference both render from the same source

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

ARG MAILPIT_VERSION=v1.29.7
ARG MAILPIT_IMAGE_DIGEST=sha256:...
FROM axllent/mailpit:${MAILPIT_VERSION}@${MAILPIT_IMAGE_DIGEST} AS mailpit
```

That is the intended pattern for this repo.
