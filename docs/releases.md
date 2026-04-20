# Releases

`infisical-aio` uses upstream-version-plus-AIO-revision releases such as `v0.159.16-aio.1`.

## Version Format

- first wrapper release for upstream `v0.159.16`: `v0.159.16-aio.1`
- second wrapper-only release on the same upstream: `v0.159.16-aio.2`
- first wrapper release after upgrading upstream again: `vX.Y.Z-aio.1`

## Published Image Tags

Every `main` build publishes:

- `latest`
- the exact pinned upstream version
- the exact release package tag like `v0.159.16-aio.1`
- `sha-<commit>`

## Release Flow

1. Trigger **Release / Template** from `main` with `action=prepare`.
2. The workflow computes the next `upstream-aio.N` version and opens a release PR.
3. Review and merge that PR into `main`.
4. Trigger **Release / Template** from `main` again with `action=publish`.
5. The workflow reads the merged `CHANGELOG.md` entry, syncs the XML `<Changes>` block, creates the Git tag, and publishes the GitHub Release.
