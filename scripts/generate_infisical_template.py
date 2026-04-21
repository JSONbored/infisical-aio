#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
DOCKERFILE = ROOT / "Dockerfile"
OUTPUT = ROOT / "infisical-aio.xml"


def docker_arg(name: str) -> str:
    pattern = re.compile(rf"^ARG {re.escape(name)}=(.+)$", re.MULTILINE)
    match = pattern.search(DOCKERFILE.read_text())
    if not match:
        raise SystemExit(f"Missing Dockerfile ARG {name}")
    return match.group(1).strip()


def fetch_env_source(version: str) -> str:
    url = f"https://raw.githubusercontent.com/Infisical/infisical/{version}/backend/src/lib/config/env.ts"
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.netloc != "raw.githubusercontent.com":
        raise SystemExit(f"Refusing to fetch env schema from unexpected URL: {url}")
    try:
        with urlopen(
            url, timeout=30
        ) as response:  # nosec B310 - scheme and host are validated immediately above
            return response.read().decode("utf-8")
    except (HTTPError, URLError) as exc:
        raise SystemExit(
            f"Unable to fetch upstream env schema from {url}: {exc}"
        ) from exc


def parse_schema_keys(source: str) -> list[str]:
    start = source.index("const envSchema = z")
    end = source.index(".refine(", start)
    block = source[start:end]
    keys: list[str] = []
    for line in block.splitlines():
        match = re.match(r"\s*([A-Z0-9_]+):", line)
        if match:
            keys.append(match.group(1))
    return keys


SKIP_KEYS = {
    "HOST",
    "PORT",
    "NODE_ENV",
    "INFISICAL_PLATFORM_VERSION",
    "BCRYPT_SALT_ROUND",
}
MASK_HINTS = ("PASSWORD", "SECRET", "TOKEN", "KEY", "CERT", "DSN")
BOOL_DEFAULTS = {
    "TELEMETRY_ENABLED": "false|true",  # nosec B105
    "QUEUE_WORKERS_ENABLED": "true|false",  # nosec B105
    "DISABLE_SECRET_SCANNING": "false|true",  # nosec B105
    "CLICKHOUSE_AUDIT_LOG_ENABLED": "true|false",  # nosec B105
    "AUDIT_LOG_STREAMS_ENABLED": "true|false",  # nosec B105
    "DISABLE_POSTGRES_AUDIT_LOG_STORAGE": "false|true",  # nosec B105
    "KUBERNETES_AUTO_FETCH_SERVICE_ACCOUNT_TOKEN": "false|true",  # nosec B105
    "SMTP_IGNORE_TLS": "false|true",  # nosec B105
    "SMTP_REQUIRE_TLS": "true|false",  # nosec B105
    "SMTP_TLS_REJECT_UNAUTHORIZED": "true|false",  # nosec B105
    "OTEL_TELEMETRY_COLLECTION_ENABLED": "false|true",  # nosec B105
    "SHOULD_USE_DATADOG_TRACER": "false|true",  # nosec B105
    "DATADOG_PROFILING_ENABLED": "false|true",  # nosec B105
    "ALLOW_INTERNAL_IP_CONNECTIONS": "false|true",  # nosec B105
    "USE_PG_QUEUE": "false|true",  # nosec B105
    "SHOULD_INIT_PG_QUEUE": "false|true",  # nosec B105
    "DYNAMIC_SECRET_ALLOW_INTERNAL_IP": "false|true",  # nosec B105
    "ENABLE_MSSQL_SECRET_ROTATION_ENCRYPT": "true|false",  # nosec B105
    "MAINTENANCE_MODE": "false|true",  # nosec B105
}
MANUAL_KEYS = {
    "SITE_URL",
    "ENCRYPTION_KEY",
    "AUTH_SECRET",
    "DB_CONNECTION_URI",
    "REDIS_URL",
    "SMTP_HOST",
    "SMTP_PORT",
    "SMTP_USERNAME",
    "SMTP_PASSWORD",
    "SMTP_FROM_ADDRESS",
    "SMTP_FROM_NAME",
    "TELEMETRY_ENABLED",
    "INITIAL_ORGANIZATION_NAME",
}


def config_name(key: str) -> str:
    if key.startswith("SMTP_"):
        return f"[SMTP] {key}"
    if key.startswith("CLIENT_") or key.startswith("DEFAULT_SAML_"):
        return f"[SSO/Auth] {key}"
    if key.startswith("INF_APP_CONNECTION_"):
        return f"[App Connections] {key}"
    if key.startswith("SECRET_SCANNING_") or key.startswith("DISABLE_SECRET_SCANNING"):
        return f"[Secret Scanning] {key}"
    if (
        key.startswith("OTEL_")
        or key.startswith("DATADOG_")
        or key.startswith("POSTHOG_")
        or key.startswith("TELEMETRY_")
    ):
        return f"[Telemetry] {key}"
    if (
        key.startswith("CLICKHOUSE_")
        or key.startswith("AUDIT_")
        or key.startswith("DISABLE_POSTGRES_AUDIT_LOG_STORAGE")
    ):
        return f"[Audit Logs] {key}"
    if key.startswith("REDIS_"):
        return f"[Redis] {key}"
    if (
        key.startswith("DB_")
        or key.startswith("SANITIZED_SCHEMA")
        or key.startswith("GENERATE_SANITIZED_SCHEMA")
    ):
        return f"[Database] {key}"
    if key.startswith("ACME_"):
        return f"[ACME] {key}"
    if key.startswith("GATEWAY_") or key.startswith("RELAY_") or key.startswith("PAM_"):
        return f"[Gateway/PAM] {key}"
    if key.startswith("HSM_"):
        return f"[HSM] {key}"
    if key.startswith("CORS_") or key.endswith("_HEADER_KEY"):
        return f"[Network/Security] {key}"
    if (
        key.startswith("LICENSE_")
        or key.startswith("INFISICAL_")
        or key in {"INFISICAL_CLOUD", "INFISICAL_DEDICATED"}
    ):
        return f"[Platform] {key}"
    return f"[Advanced] {key}"


def description_for(key: str) -> str:
    custom = {
        "SITE_URL": "Canonical public URL for your instance, including http or https. This should match the real URL users and reverse proxies will use.",
        "ENCRYPTION_KEY": "Optional manual override for the platform encryption key. Leave blank to let the wrapper generate and persist it automatically.",
        "AUTH_SECRET": "Optional manual override for the JWT auth secret. Leave blank to let the wrapper generate and persist it automatically.",  # nosec B105
        "DB_CONNECTION_URI": "Leave blank for the bundled PostgreSQL database. Set this to use an external Postgres instance instead.",
        "REDIS_URL": "Leave blank for the bundled Redis instance. Set this to use an external Redis instance instead.",
        "SMTP_HOST": "Optional SMTP server hostname for transactional email features such as invites and MFA email flows.",
        "SMTP_PORT": "SMTP server port. Default upstream value is 587.",
        "SMTP_USERNAME": "Optional SMTP username.",
        "SMTP_PASSWORD": "Optional SMTP password.",  # nosec B105
        "SMTP_FROM_ADDRESS": "Optional sender email address used for Infisical emails.",
        "SMTP_FROM_NAME": "Optional sender display name. Default is Infisical.",
        "TELEMETRY_ENABLED": "Usage telemetry toggle. The AIO wrapper defaults this to false for privacy-first self-hosting.",
        "INITIAL_ORGANIZATION_NAME": "Optional default organization name shown during initial signup when you are not using API bootstrap.",
    }
    return custom.get(key, f"Advanced upstream Infisical environment variable `{key}`.")


def render_config(key: str) -> str:
    default = BOOL_DEFAULTS.get(key, "")
    value = default.split("|", 1)[0] if "|" in default else default
    mask = "true" if any(part in key for part in MASK_HINTS) else "false"
    description = html.escape(description_for(key), quote=True)
    return (
        f'  <Config Name="{html.escape(config_name(key), quote=True)}" '
        f'Target="{html.escape(key, quote=True)}" Default="{html.escape(default, quote=True)}" '
        f'Mode="" Description="{description}" Type="Variable" Display="advanced" Required="false" Mask="{mask}">'
        f"{html.escape(value)}</Config>"
    )


def render_xml() -> str:
    version = docker_arg("UPSTREAM_VERSION")
    env_source = fetch_env_source(version)
    keys = [
        key
        for key in parse_schema_keys(env_source)
        if key not in SKIP_KEYS and key not in MANUAL_KEYS
    ]
    configs = "\n".join(render_config(key) for key in keys)
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
`infisical-aio` wraps the official Infisical container and bundles the required PostgreSQL and Redis services into one Unraid-first install path. That keeps the beginner setup small while still exposing the wider upstream configuration surface in Advanced View.&#xD;
&#xD;
[b]Quick Install (Beginners)[/b]&#xD;
1. Install the template and keep the default `/config` and `/data` paths unless you have a reason to move them.&#xD;
2. Set [code]SITE_URL[/code] to the real URL users will visit, such as [code]https://secrets.example.com[/code] or [code]http://tower.local:8080[/code].&#xD;
3. Start the container. The wrapper will auto-generate and persist [code]ENCRYPTION_KEY[/code] and [code]AUTH_SECRET[/code] if you leave them blank.&#xD;
4. Either create the first account in the UI, or fill the optional [code]AIO_BOOTSTRAP_*[/code] fields in Advanced View to bootstrap the first admin and organization automatically.&#xD;
&#xD;
[b]Power Users (Advanced View)[/b]&#xD;
- Advanced View exposes the broader Infisical self-hosting environment surface, including SMTP, SSO, audit logging, telemetry, secret scanning, app connections, gateway/PAM controls, and expert network/security knobs.&#xD;
- Leave [code]DB_CONNECTION_URI[/code] and [code]REDIS_URL[/code] blank for the easiest bundled path. Set them only if you want to use external PostgreSQL or Redis instead of the embedded services.&#xD;
- If you enable Prometheus metrics export, publish the optional [code]9464[/code] metrics port in Advanced View so your scraper can reach it.&#xD;
&#xD;
[b]Important Notes[/b]&#xD;
- The default AIO path embeds PostgreSQL and Redis for convenience. That is simpler for first boot, but it is not the same as a highly available production deployment.&#xD;
- Infisical itself recommends external high-availability PostgreSQL and Redis for more serious production deployments.&#xD;
- [code]SITE_URL[/code] matters. If you set it wrong, browser flows, links, email behavior, and some integrations will break in subtle ways.&#xD;
- If you enable automatic bootstrap, you are creating a highly privileged instance-admin identity during first boot. Treat those credentials carefully.</Overview>
  <Changes>### 2026-04-20&#xD;
- Initial public release has not been cut yet.&#xD;
- The source repo is validating the bundled PostgreSQL 16 + Redis 7 wrapper, first-run secret persistence, and the generated Infisical config surface.</Changes>
  <Category>Network:Security Tools:Utilities</Category>
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

  <Config Name="Web UI Port" Target="8080" Default="8080" Mode="tcp" Description="Main Infisical web and API port." Type="Port" Display="always" Required="true" Mask="false">8080</Config>
  <Config Name="Prometheus Metrics Port" Target="9464" Default="" Mode="tcp" Description="Optional host port for OTEL Prometheus metrics. Leave blank unless you enable OTEL_TELEMETRY_COLLECTION_ENABLED=true and OTEL_EXPORT_TYPE=prometheus." Type="Port" Display="advanced" Required="false" Mask="false"></Config>
  <Config Name="AppData - Config" Target="/config" Default="/mnt/user/appdata/infisical-aio/config" Mode="rw" Description="Persistent wrapper state, generated first-run secrets, and optional bootstrap artifacts." Type="Path" Display="always" Required="true" Mask="false">/mnt/user/appdata/infisical-aio/config</Config>
  <Config Name="AppData - Data" Target="/data" Default="/mnt/user/appdata/infisical-aio/data" Mode="rw" Description="Persistent bundled PostgreSQL and Redis data for the default AIO path." Type="Path" Display="always" Required="true" Mask="false">/mnt/user/appdata/infisical-aio/data</Config>
  <Config Name="Site URL" Target="SITE_URL" Default="http://tower.local:8080" Mode="" Description="Canonical public URL for your instance, including http or https. This should match the real URL users and reverse proxies will use." Type="Variable" Display="always" Required="true" Mask="false">http://tower.local:8080</Config>

  <Config Name="Encryption Key" Target="ENCRYPTION_KEY" Default="" Mode="" Description="Optional manual override for the platform encryption key. Leave blank to let the wrapper generate and persist it automatically." Type="Variable" Display="advanced" Required="false" Mask="true"/>
  <Config Name="Auth Secret" Target="AUTH_SECRET" Default="" Mode="" Description="Optional manual override for the JWT auth secret. Leave blank to let the wrapper generate and persist it automatically." Type="Variable" Display="advanced" Required="false" Mask="true"/>
  <Config Name="Initial Organization Name" Target="INITIAL_ORGANIZATION_NAME" Default="" Mode="" Description="Optional default organization name shown during initial signup when you are not using API bootstrap." Type="Variable" Display="advanced" Required="false" Mask="false"/>
  <Config Name="External PostgreSQL DB_CONNECTION_URI" Target="DB_CONNECTION_URI" Default="" Mode="" Description="Leave blank for the bundled PostgreSQL database. Set this to use an external Postgres instance instead." Type="Variable" Display="advanced" Required="false" Mask="true"/>
  <Config Name="External Redis REDIS_URL" Target="REDIS_URL" Default="" Mode="" Description="Leave blank for the bundled Redis instance. Set this to use an external Redis instance instead." Type="Variable" Display="advanced" Required="false" Mask="true"/>
  <Config Name="[Network/Security] NODE_EXTRA_CA_CERTS" Target="NODE_EXTRA_CA_CERTS" Default="" Mode="" Description="Optional path to a PEM CA bundle inside the container for private or self-signed upstream certificates, such as external Redis over rediss://. Because /config is persistent, a typical path is /config/aio/certs/custom-ca.pem." Type="Variable" Display="advanced" Required="false" Mask="false"/>

  <Config Name="Auto Bootstrap Admin Email" Target="AIO_BOOTSTRAP_EMAIL" Default="" Mode="" Description="Optional first admin email for automatic instance bootstrap. Leave blank to bootstrap manually in the UI." Type="Variable" Display="advanced" Required="false" Mask="false"/>
  <Config Name="Auto Bootstrap Admin Password" Target="AIO_BOOTSTRAP_PASSWORD" Default="" Mode="" Description="Optional first admin password for automatic instance bootstrap." Type="Variable" Display="advanced" Required="false" Mask="true"/>
  <Config Name="Auto Bootstrap Organization" Target="AIO_BOOTSTRAP_ORGANIZATION" Default="" Mode="" Description="Optional organization name used by the automatic bootstrap flow." Type="Variable" Display="advanced" Required="false" Mask="false"/>
  <Config Name="Auto Bootstrap Save Response" Target="AIO_BOOTSTRAP_SAVE_RESPONSE" Default="false|true" Mode="" Description="When true, the bootstrap API response is persisted to /config/aio/bootstrap-response.json. Treat that file like a root credential." Type="Variable" Display="advanced" Required="false" Mask="false">false</Config>

  <Config Name="[SMTP] SMTP_HOST" Target="SMTP_HOST" Default="" Mode="" Description="Optional SMTP server hostname for transactional email features such as invites and MFA email flows." Type="Variable" Display="advanced" Required="false" Mask="false"/>
  <Config Name="[SMTP] SMTP_PORT" Target="SMTP_PORT" Default="" Mode="" Description="SMTP server port. Default upstream value is 587." Type="Variable" Display="advanced" Required="false" Mask="false"/>
  <Config Name="[SMTP] SMTP_USERNAME" Target="SMTP_USERNAME" Default="" Mode="" Description="Optional SMTP username." Type="Variable" Display="advanced" Required="false" Mask="false"/>
  <Config Name="[SMTP] SMTP_PASSWORD" Target="SMTP_PASSWORD" Default="" Mode="" Description="Optional SMTP password." Type="Variable" Display="advanced" Required="false" Mask="true"/>
  <Config Name="[SMTP] SMTP_FROM_ADDRESS" Target="SMTP_FROM_ADDRESS" Default="" Mode="" Description="Optional sender email address used for Infisical emails." Type="Variable" Display="advanced" Required="false" Mask="false"/>
  <Config Name="[SMTP] SMTP_FROM_NAME" Target="SMTP_FROM_NAME" Default="" Mode="" Description="Optional sender display name. Default is Infisical." Type="Variable" Display="advanced" Required="false" Mask="false"/>
  <Config Name="[Telemetry] TELEMETRY_ENABLED" Target="TELEMETRY_ENABLED" Default="false|true" Mode="" Description="Usage telemetry toggle. The AIO wrapper defaults this to false for privacy-first self-hosting." Type="Variable" Display="advanced" Required="false" Mask="false">false</Config>

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
                f"{output_path} is out of date with the current upstream env schema. "
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
