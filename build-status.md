# Build Status

Current status of the `infisical-aio` source repo before publish and CA sync.

## Implemented

- pinned the official `infisical/infisical` image by upstream version and digest
- bundled PostgreSQL and Redis defaults for the single-container Unraid path
- generated first-run secret persistence under `/config/aio/generated.env`
- optional bootstrap automation via the documented `/api/v1/admin/bootstrap` endpoint
- repo-specific smoke test, upstream tracking, and runtime wrapper behavior

## Remaining Before Publish

- replace the placeholder icon in `assets/app-icon.png`
- rerun strict validation and the broader local container test matrix
- review the generated XML output for any final naming or grouping tweaks
- publish the image, then sync XML and icon into `awesome-unraid`
