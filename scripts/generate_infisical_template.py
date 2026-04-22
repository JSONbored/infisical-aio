#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path

from config_surface import collect_validation_errors, render_xml_configs

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "infisical-aio.xml"
CHANGELOG = ROOT / "CHANGELOG.md"


def fallback_changes() -> str:
    body = (
        "### 2026-04-20\n"
        "- Generated from CHANGELOG.md during release preparation. Do not edit manually.\n"
        "- Initial public release has not been cut yet.\n"
        "- The source repo is validating the bundled PostgreSQL 16 + Redis 7 wrapper, "
        "local Mailpit inbox integration, first-run secret persistence, and the generated "
        "Infisical config surface."
    )
    return html.escape(body, quote=False).replace("\n", "&#xD;\n")


def latest_changelog_version(changelog: Path) -> str | None:
    pattern = re.compile(r"^##\s+(?:\[([^\]]+)\]\([^)]+\)|([^\s]+))")
    for line in changelog.read_text().splitlines():
        match = pattern.match(line.strip())
        if not match:
            continue
        version = match.group(1) or match.group(2)
        if version != "Unreleased":
            return version
    return None


def extract_release_notes(version: str, changelog: Path) -> str:
    heading = re.compile(
        rf"^##\s+(?:\[{re.escape(version)}\]\([^)]+\)|{re.escape(version)})(?:\s+-\s+.+)?$"
    )
    next_heading = re.compile(r"^##\s+")
    lines = changelog.read_text().splitlines()
    start = None
    for idx, line in enumerate(lines):
        if heading.match(line.strip()):
            start = idx + 1
            break
    if start is None:
        raise ValueError(f"Unable to find release section for {version} in {changelog}")
    end = len(lines)
    for idx in range(start, len(lines)):
        if next_heading.match(lines[idx].strip()):
            end = idx
            break
    notes = "\n".join(lines[start:end]).strip()
    if not notes:
        raise ValueError(f"Release section for {version} in {changelog} is empty")
    return notes


def release_heading(version: str, changelog: Path) -> str:
    heading = re.compile(
        rf"^##\s+(?:\[{re.escape(version)}\]\([^)]+\)|{re.escape(version)})(?:\s+-\s+(.+))?$"
    )
    for line in changelog.read_text().splitlines():
        match = heading.match(line.strip())
        if match:
            release_date = (match.group(1) or "").strip()
            if release_date:
                return f"### {release_date}"
            break
    return f"### {version}"


def render_changes() -> str:
    if not CHANGELOG.exists():
        return fallback_changes()
    version = latest_changelog_version(CHANGELOG)
    if not version:
        return fallback_changes()
    try:
        notes = extract_release_notes(version, CHANGELOG)
    except ValueError:
        return fallback_changes()

    lines: list[str] = [
        release_heading(version, CHANGELOG),
        "- Generated from CHANGELOG.md during release preparation. Do not edit manually.",
    ]
    for line in notes.splitlines():
        stripped = line.rstrip()
        if not stripped:
            continue
        if stripped.startswith("<!--") and stripped.endswith("-->"):
            continue
        if re.match(r"^\[[^\]]+\]:\s+https?://", stripped):
            continue
        if stripped.startswith("Full Changelog:"):
            continue
        if stripped.startswith("## "):
            continue
        if stripped.startswith("### "):
            continue
        if stripped.startswith("- "):
            lines.append(stripped)
            continue
        lines.append(f"- {stripped.lstrip('- ').strip()}")
    return html.escape("\n".join(lines).strip(), quote=False).replace("\n", "&#xD;\n")


def render_xml() -> str:
    errors = collect_validation_errors()
    if errors:
        raise SystemExit("\n".join(errors))

    configs = render_xml_configs()
    changes = render_changes()
    return f"""<?xml version="1.0"?>
<Container version="2">
  <Name>infisical-aio</Name>
  <Repository>jsonbored/infisical-aio:latest</Repository>
  <Registry>https://hub.docker.com/r/jsonbored/infisical-aio</Registry>
  <Network>bridge</Network>
  <MyIP/>
  <Shell>sh</Shell>
  <Privileged>false</Privileged>
  <Support>https://github.com/JSONbored/infisical-aio/issues</Support>
  <Project>https://github.com/JSONbored/infisical-aio</Project>
  <Overview>Infisical is an open-source secrets management platform for teams, infrastructure, and application credentials.&#xD;
&#xD;
[b]All-In-One Unraid Edition[/b]&#xD;
`infisical-aio` wraps the official Infisical container and bundles the required PostgreSQL and Redis services into one Unraid-first install path. It also includes a bundled Mailpit inbox so default startup and local email-dependent flows work without forcing a real SMTP relay on day one. That keeps the beginner setup small while still exposing the wider upstream configuration surface in Advanced View.&#xD;
&#xD;
[b]Quick Install (Beginners)[/b]&#xD;
1. Install the template and keep the default `/config` and `/data` paths unless you have a reason to move them.&#xD;
2. Set [code]SITE_URL[/code] to the real URL users will visit, such as [code]https://secrets.example.com[/code] or [code]http://tower.local:8080[/code].&#xD;
3. Start the container. The wrapper will auto-generate and persist [code]ENCRYPTION_KEY[/code] and [code]AUTH_SECRET[/code] if you leave them blank, and the bundled Mailpit inbox UI will be reachable on port [code]8025[/code] using credentials stored in [code]/config/aio/generated.env[/code].&#xD;
4. Either create the first account in the UI, or fill the optional [code]AIO_BOOTSTRAP_*[/code] fields in Advanced View to bootstrap the first admin and organization automatically.&#xD;
&#xD;
[b]Power Users (Advanced View)[/b]&#xD;
- Advanced View exposes the broader Infisical self-hosting environment surface, including SMTP, SSO, audit logging, telemetry, secret scanning, app connections, gateway/PAM controls, and expert network/security knobs.&#xD;
- Leave [code]DB_CONNECTION_URI[/code] and [code]REDIS_URL[/code] blank for the easiest bundled path. Set them only if you want to use external PostgreSQL or Redis instead of the embedded services.&#xD;
- Leave [code]SMTP_HOST[/code] blank for the bundled local Mailpit inbox, or point it at a real external SMTP server if you do not want the bundled inbox.&#xD;
- If you enable Prometheus metrics export, publish the optional [code]9464[/code] metrics port in Advanced View so your scraper can reach it.&#xD;
&#xD;
[b]Important Notes[/b]&#xD;
- The default AIO path embeds PostgreSQL and Redis for convenience. That is simpler for first boot, but it is not the same as a highly available production deployment.&#xD;
- Infisical itself recommends external high-availability PostgreSQL and Redis for more serious production deployments.&#xD;
- The bundled Mailpit inbox is for local or lab use. It is not a production mail relay and should not be confused with real deliverability infrastructure.&#xD;
- [code]SITE_URL[/code] matters. If you set it wrong, browser flows, links, email behavior, and some integrations will break in subtle ways.&#xD;
- If you enable automatic bootstrap, you are creating a highly privileged instance-admin identity during first boot. Treat those credentials carefully.</Overview>
  <Changes>{changes}</Changes>
  <Category>Network:Security Security Tools:Utilities</Category>
  <WebUI>http://[IP]:[PORT:8080]</WebUI>
  <TemplateURL>https://raw.githubusercontent.com/JSONbored/awesome-unraid/main/infisical-aio.xml</TemplateURL>
  <Icon>https://raw.githubusercontent.com/JSONbored/awesome-unraid/main/icons/infisical.png</Icon>
  <ExtraSearchTerms>secrets manager vault devops credentials certificates pki pam secret scanning self-hosted</ExtraSearchTerms>
  <Requires>Use a correct public or LAN [code]SITE_URL[/code] and back up both your PostgreSQL data and the persisted [code]ENCRYPTION_KEY[/code]. For larger or higher-availability deployments, move PostgreSQL and Redis out of the bundled container and use the advanced external override fields.</Requires>
  <ExtraParams/>
  <PostArgs/>
  <CPUset/>
  <DateInstalled/>
  <DonateText>Support JSONbored on GitHub Sponsors.</DonateText>
  <DonateLink>https://github.com/sponsors/JSONbored</DonateLink>
  <Description/>
  <Networking>
    <Mode>bridge</Mode>
    <Publish>
      <Port>
        <HostPort>8080</HostPort>
        <ContainerPort>8080</ContainerPort>
        <Protocol>tcp</Protocol>
      </Port>
      <Port>
        <HostPort>8025</HostPort>
        <ContainerPort>8025</ContainerPort>
        <Protocol>tcp</Protocol>
      </Port>
    </Publish>
  </Networking>
  <Data>
    <Volume>
      <HostDir>/mnt/user/appdata/infisical-aio/config</HostDir>
      <ContainerDir>/config</ContainerDir>
      <Mode>rw</Mode>
    </Volume>
    <Volume>
      <HostDir>/mnt/user/appdata/infisical-aio/data</HostDir>
      <ContainerDir>/data</ContainerDir>
      <Mode>rw</Mode>
    </Volume>
  </Data>
  <Environment/>

{configs}
</Container>
"""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate the canonical infisical-aio Community Apps template."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=OUTPUT,
        help="Where to write the generated XML.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if the generated XML does not match the current output file.",
    )
    args = parser.parse_args()

    rendered = render_xml()
    output_path = args.output
    if args.check:
        existing = output_path.read_text() if output_path.exists() else ""
        if existing != rendered:
            print(
                f"{output_path} is out of date with the generated template. "
                "Run scripts/generate_infisical_template.py to refresh it.",
                file=sys.stderr,
            )
            return 1
        print(f"{output_path} matches the generated template")
        return 0

    output_path.write_text(rendered)
    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
