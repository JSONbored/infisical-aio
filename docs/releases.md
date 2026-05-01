# Releases

`infisical-aio` uses upstream-version-plus-AIO-revision releases such as `v0.159.16-aio.1`.

## Version Format

- first wrapper release for upstream `v0.159.16`: `v0.159.16-aio.1`
- second wrapper-only release on the same upstream: `v0.159.16-aio.2`
- first wrapper release after upgrading upstream again: `vX.Y.Z-aio.1`

## Published Image Tags

Every central `aio-fleet` publish for `main` publishes:

- `latest`
- the exact pinned upstream version
- `sha-<commit>`

Release commits also publish the exact immutable release package tag, for example `v0.159.16-aio.1`. Ordinary `main` pushes do not overwrite that release tag.

Central publish uses Docker Hub credentials and the shared GHCR token stored in `aio-fleet`.

## Release Flow

1. From `aio-fleet`, run `python -m aio_fleet release status --repo infisical-aio` to inspect the next release.
2. Run `python -m aio_fleet release prepare --repo infisical-aio` on a release branch, then open a `chore(release): <version>` PR.
3. Review and merge that PR into `main`.
4. Run the central `aio-fleet` control check for the release target commit with publish enabled, and require `aio-fleet / required` to pass.
5. Run `python -m aio_fleet release publish --repo infisical-aio` from `aio-fleet` to create the GitHub Release.
