# Recommended GitHub Settings

Apply these before pushing `infisical-aio` fully public.

## General

- keep the repo private until the image, docs, and Actions are validated
- set a clear About description and relevant GitHub topics
- confirm the Docker Hub repository is public and pullable after the first successful publish

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

- `aio-fleet / required`

## Security

- enable dependency graph and GitHub vulnerability alerts
- enable private vulnerability reporting and keep `SECURITY.md` aligned with the live reporting path
- enable secret scanning
- enable push protection
- keep shared dependency and upstream policy in `aio-fleet`

## Secrets and Variables

App repos should not carry repo-local workflow secrets for shared automation. Configure the GitHub App, Docker Hub credentials, and GHCR token in `aio-fleet`; keep app-local secrets only when the runtime itself needs them.
