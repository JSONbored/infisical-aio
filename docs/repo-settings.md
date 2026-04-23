# Recommended GitHub Settings

Apply these before pushing `infisical-aio` fully public.

## General

- keep the repo private until the image, docs, and Actions are validated
- set a clear About description and relevant GitHub topics
- make the GHCR package public only after the first successful publish

## Branch Protection

Create a ruleset for `main`:

- require pull request before merge
- require status checks to pass before merge
- require signed commits
- require linear history
- block force pushes
- block branch deletion
- include administrators

Suggested required checks:

- `validate-template`
- `unit-tests`
- `integration-tests`
- `pinned-actions`
- `dependency-review`

## Security

- enable dependency graph and GitHub vulnerability alerts
- enable private vulnerability reporting and keep `SECURITY.md` aligned with the live reporting path
- enable secret scanning
- enable push protection
- use Renovate for update PRs instead of Dependabot update PRs

## Secrets and Variables

Required secret:

- `SYNC_TOKEN`
