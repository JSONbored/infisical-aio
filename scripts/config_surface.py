from __future__ import annotations

import html
import re
import tomllib
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
DOCKERFILE = ROOT / "Dockerfile"
MANIFEST_PATH = ROOT / "config_surface.toml"

MASK_HINTS = ("PASSWORD", "SECRET", "TOKEN", "KEY", "CERT", "DSN")
RUNTIME_MODE_VALUES = {
    "always",
    "bootstrap-only",
    "bundled-only",
    "external-service",
}
RUNTIME_INTERNAL_ENV_KEYS = {
    "AIO_ENV_FILE",
    "AIO_INTERNAL_DB_PASSWORD",
    "BOOTSTRAP_MARKER",
    "BOOTSTRAP_RESPONSE",
    "BOOTSTRAP_URL",
    "ENV_FILE",
    "HOME",
    "INTERNAL_PG_PASS",
    "LOGNAME",
    "MAILPIT_DIR",
    "MAILPIT_UI_AUTH_FILE",
    "PATH",
    "PG_BIN_DIR",
    "PORT_VALUE",
    "SAVE_RESPONSE",
    "SECONDS",
    "STATUS_URL",
    "USER",
}


@dataclass(frozen=True)
class ConfigItem:
    group_id: str
    source: str
    kind: str
    section: str
    target: str
    name: str
    description: str
    display: str
    required: bool
    runtime_mode: str
    default: str
    value: str | None
    mask: bool
    persist_if_missing: bool
    bundled_default: str | None
    behavior: str | None

    @property
    def xml_mode(self) -> str:
        if self.kind == "port":
            return "tcp"
        if self.kind == "path":
            return "rw"
        return ""

    @property
    def xml_type(self) -> str:
        if self.kind == "port":
            return "Port"
        if self.kind == "path":
            return "Path"
        return "Variable"


def docker_arg(name: str) -> str:
    pattern = re.compile(rf"^ARG {re.escape(name)}=(.+)$", re.MULTILINE)
    match = pattern.search(DOCKERFILE.read_text())
    if not match:
        raise ValueError(f"Missing Dockerfile ARG {name}")
    return match.group(1).strip()


def load_manifest(path: Path = MANIFEST_PATH) -> dict:
    return tomllib.loads(path.read_text())


def _normalize_raw_item(raw_item: str | dict) -> dict:
    if isinstance(raw_item, str):
        return {"target": raw_item}
    return dict(raw_item)


def _infer_mask(target: str) -> bool:
    return any(part in target for part in MASK_HINTS)


def _default_value(default: str, explicit_value: str | None) -> str | None:
    if explicit_value is not None:
        return explicit_value or None
    if not default:
        return None
    return default.split("|", 1)[0]


def resolve_config_items(manifest: dict | None = None) -> list[ConfigItem]:
    manifest = manifest or load_manifest()
    items: list[ConfigItem] = []

    for group in manifest["groups"]:
        group_defaults = {
            "display": group.get("display", "advanced"),
            "required": bool(group.get("required", False)),
            "runtime_mode": group.get("runtime_mode", "always"),
            "default": str(group.get("default", "")),
            "value": group.get("value"),
            "mask": group.get("mask"),
            "persist_if_missing": bool(group.get("persist_if_missing", False)),
            "bundled_default": group.get("bundled_default"),
            "behavior": group.get("behavior"),
        }
        prefix = group.get("name_prefix", "")
        source = group["source"]
        kind = group["kind"]
        section = group["section"]

        for raw_item in group["items"]:
            item = _normalize_raw_item(raw_item)
            target = str(item["target"])
            default = str(item.get("default", group_defaults["default"]))
            explicit_value = item.get("value", group_defaults["value"])
            value = _default_value(default, explicit_value)
            name = item.get("name") or f"{prefix}{target}"
            description = item.get("description")
            if not description:
                if source == "upstream":
                    description = (
                        f"Advanced upstream Infisical environment variable `{target}`."
                    )
                else:
                    description = f"Repository-specific configuration `{target}`."

            items.append(
                ConfigItem(
                    group_id=group["id"],
                    source=source,
                    kind=kind,
                    section=section,
                    target=target,
                    name=name,
                    description=description,
                    display=str(item.get("display", group_defaults["display"])),
                    required=bool(item.get("required", group_defaults["required"])),
                    runtime_mode=str(
                        item.get("runtime_mode", group_defaults["runtime_mode"])
                    ),
                    default=default,
                    value=value,
                    mask=(
                        bool(item.get("mask", group_defaults["mask"]))
                        if item.get("mask", group_defaults["mask"]) is not None
                        else _infer_mask(target)
                    ),
                    persist_if_missing=bool(
                        item.get(
                            "persist_if_missing",
                            group_defaults["persist_if_missing"],
                        )
                    ),
                    bundled_default=(
                        str(
                            item.get(
                                "bundled_default",
                                group_defaults["bundled_default"],
                            )
                        )
                        if item.get(
                            "bundled_default", group_defaults["bundled_default"]
                        )
                        is not None
                        else None
                    ),
                    behavior=(
                        str(item.get("behavior", group_defaults["behavior"]))
                        if item.get("behavior", group_defaults["behavior"]) is not None
                        else None
                    ),
                )
            )

    return items


def validate_manifest(manifest: dict | None = None) -> list[str]:
    manifest = manifest or load_manifest()
    items = resolve_config_items(manifest)
    errors: list[str] = []
    seen_targets: set[str] = set()

    if manifest.get("schema_version") != 1:
        errors.append("config_surface.toml schema_version must be 1")

    for item in items:
        if item.target in seen_targets:
            errors.append(f"Duplicate config target in manifest: {item.target}")
        seen_targets.add(item.target)

        if item.source not in {"repo", "upstream"}:
            errors.append(f"{item.target} has unsupported source {item.source!r}")
        if item.kind not in {"path", "port", "variable"}:
            errors.append(f"{item.target} has unsupported kind {item.kind!r}")
        if item.runtime_mode not in RUNTIME_MODE_VALUES:
            errors.append(
                f"{item.target} has unsupported runtime_mode {item.runtime_mode!r}"
            )
        if item.display not in {"always", "advanced"}:
            errors.append(f"{item.target} has unsupported display {item.display!r}")

    return errors


def fetch_upstream_env_source(
    version: str | None = None, manifest: dict | None = None
) -> str:
    manifest = manifest or load_manifest()
    version = version or docker_arg("UPSTREAM_VERSION")
    url = manifest["upstream"]["env_source"].format(version=version)
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.netloc != "raw.githubusercontent.com":
        raise ValueError(f"Refusing to fetch env schema from unexpected URL: {url}")
    try:
        with urlopen(
            url, timeout=30
        ) as response:  # nosec B310 - scheme and host are validated immediately above
            return response.read().decode("utf-8")
    except (HTTPError, URLError) as exc:
        raise RuntimeError(
            f"Unable to fetch upstream env schema from {url}: {exc}"
        ) from exc


def parse_upstream_env_keys(
    source: str | None = None, manifest: dict | None = None
) -> list[str]:
    manifest = manifest or load_manifest()
    source = source or fetch_upstream_env_source(manifest=manifest)
    start_marker = manifest["upstream"]["schema_start"]
    end_marker = manifest["upstream"]["schema_end"]
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    block = source[start:end]
    keys: list[str] = []
    for line in block.splitlines():
        match = re.match(r"\s*([A-Z0-9_]+):", line)
        if match:
            keys.append(match.group(1))
    return keys


def validate_upstream_alignment(manifest: dict | None = None) -> list[str]:
    manifest = manifest or load_manifest()
    upstream_keys = set(parse_upstream_env_keys(manifest=manifest))
    skip_keys = set(manifest["upstream"]["skip_keys"])
    manifest_upstream_keys = {
        item.target
        for item in resolve_config_items(manifest)
        if item.source == "upstream" and item.kind == "variable"
    }
    expected_keys = upstream_keys - skip_keys

    missing = sorted(expected_keys - manifest_upstream_keys)
    extra = sorted(manifest_upstream_keys - expected_keys)
    errors: list[str] = []
    if missing:
        errors.append(
            "config_surface.toml is missing upstream env keys: " + ", ".join(missing)
        )
    if extra:
        errors.append(
            "config_surface.toml declares upstream env keys that are not present in the pinned upstream schema: "
            + ", ".join(extra)
        )
    return errors


def runtime_shell_paths(root: Path = ROOT) -> list[Path]:
    paths = [
        root / "rootfs/usr/local/bin/env-helpers.sh",
        root / "rootfs/usr/local/bin/bootstrap-infisical.sh",
    ]
    paths.extend(sorted((root / "rootfs/etc/cont-init.d").glob("*")))
    paths.extend(sorted((root / "rootfs/etc/services.d").glob("*/run")))
    return [path for path in paths if path.is_file()]


def extract_shell_env_refs(path: Path) -> set[str]:
    text = path.read_text()
    return set(re.findall(r"\$(?:\{)?([A-Z][A-Z0-9_]+)(?=[^A-Z0-9_.]|$)", text))


def validate_runtime_env_surface(manifest: dict | None = None) -> list[str]:
    manifest = manifest or load_manifest()
    exposed_keys = {item.target for item in resolve_config_items(manifest)}
    allowed_keys = (
        exposed_keys
        | set(manifest["upstream"]["skip_keys"])
        | RUNTIME_INTERNAL_ENV_KEYS
    )

    errors: list[str] = []
    for path in runtime_shell_paths():
        unknown = sorted(extract_shell_env_refs(path) - allowed_keys)
        if unknown:
            errors.append(
                f"{path.relative_to(ROOT)} references env vars not declared in config_surface.toml: "
                + ", ".join(unknown)
            )
    return errors


def persisted_keys_from_bootstrap(
    path: Path | None = None,
) -> set[str]:
    path = path or ROOT / "rootfs/etc/cont-init.d/01-bootstrap.sh"
    text = path.read_text()
    return set(re.findall(r'persist_if_missing "([A-Z0-9_]+)"', text))


def validate_bootstrap_persisted_keys(manifest: dict | None = None) -> list[str]:
    manifest = manifest or load_manifest()
    exposed_persisted_keys = {
        item.target
        for item in resolve_config_items(manifest)
        if item.persist_if_missing
    }
    internal_persisted_keys = {"AIO_INTERNAL_DB_PASSWORD", "HOST", "NODE_ENV", "PORT"}
    actual = persisted_keys_from_bootstrap()
    expected = exposed_persisted_keys | internal_persisted_keys

    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    errors: list[str] = []
    if missing:
        errors.append(
            "01-bootstrap.sh is missing persist_if_missing declarations for: "
            + ", ".join(missing)
        )
    if extra:
        errors.append(
            "01-bootstrap.sh persists keys not modeled in config_surface.toml: "
            + ", ".join(extra)
        )
    return errors


def bundled_mailpit_defaults_from_runtime(
    path: Path | None = None,
) -> dict[str, str]:
    path = path or ROOT / "rootfs/usr/local/bin/env-helpers.sh"
    text = path.read_text()
    match = re.search(
        r"configure_bundled_mailpit_env\(\) \{(?P<body>.*?)^\}",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if not match:
        raise ValueError(
            "Unable to find configure_bundled_mailpit_env() in env-helpers.sh"
        )

    defaults: dict[str, str] = {}
    for env_key, value in re.findall(
        r'export ([A-Z0-9_]+)="\$\{[^:]+:-([^}]*)\}"',
        match.group("body"),
    ):
        defaults[env_key] = value
    return defaults


def validate_bundled_mailpit_defaults(manifest: dict | None = None) -> list[str]:
    manifest = manifest or load_manifest()
    expected = {
        item.target: item.bundled_default
        for item in resolve_config_items(manifest)
        if item.bundled_default is not None
    }
    actual = bundled_mailpit_defaults_from_runtime()

    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    mismatched = sorted(
        key for key in expected.keys() & actual.keys() if expected[key] != actual[key]
    )

    errors: list[str] = []
    if missing:
        errors.append(
            "configure_bundled_mailpit_env() is missing bundled defaults for: "
            + ", ".join(missing)
        )
    if extra:
        errors.append(
            "configure_bundled_mailpit_env() sets bundled defaults not modeled in config_surface.toml: "
            + ", ".join(extra)
        )
    for key in mismatched:
        errors.append(
            f"{key} bundled default mismatch: manifest={expected[key]!r}, runtime={actual[key]!r}"
        )
    return errors


def collect_validation_errors(manifest: dict | None = None) -> list[str]:
    manifest = manifest or load_manifest()
    errors: list[str] = []
    errors.extend(validate_manifest(manifest))
    errors.extend(validate_upstream_alignment(manifest))
    errors.extend(validate_runtime_env_surface(manifest))
    errors.extend(validate_bootstrap_persisted_keys(manifest))
    errors.extend(validate_bundled_mailpit_defaults(manifest))
    return errors


def render_xml_config(item: ConfigItem) -> str:
    description = html.escape(item.description, quote=True)
    value = html.escape(item.value, quote=True) if item.value is not None else ""
    return (
        f'  <Config Name="{html.escape(item.name, quote=True)}" '
        f'Target="{html.escape(item.target, quote=True)}" '
        f'Default="{html.escape(item.default, quote=True)}" '
        f'Mode="{html.escape(item.xml_mode, quote=True)}" '
        f'Description="{description}" '
        f'Type="{item.xml_type}" '
        f'Display="{item.display}" '
        f'Required="{str(item.required).lower()}" '
        f'Mask="{str(item.mask).lower()}">{value}</Config>'
    )


def render_xml_configs(manifest: dict | None = None) -> str:
    manifest = manifest or load_manifest()
    return "\n".join(render_xml_config(item) for item in resolve_config_items(manifest))


def config_reference_path(manifest: dict | None = None) -> Path:
    manifest = manifest or load_manifest()
    return ROOT / manifest["docs"]["reference_path"]


def _markdown_cell(text: str) -> str:
    return text.replace("|", "\\|")


def _config_label(item: ConfigItem) -> str:
    if item.name == item.target or item.name.endswith(f" {item.target}"):
        return f"`{item.target}`"
    return f"{item.name} (`{item.target}`)"


def _default_behavior_summary(item: ConfigItem) -> str:
    parts: list[str] = []
    if item.default:
        if "|" in item.default:
            parts.append(f"Template options: `{item.default}`")
        else:
            parts.append(f"Template default: `{item.default}`")
    if item.persist_if_missing:
        parts.append("Persisted if blank on first boot")
    if item.bundled_default is not None:
        parts.append(f"Bundled default: `{item.bundled_default}`")
    if item.behavior:
        parts.append(item.behavior)
    return "; ".join(parts) or "-"


def _render_markdown_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    widths = [len(header) for header in headers]
    for row in rows:
        for idx, cell in enumerate(row):
            widths[idx] = max(widths[idx], len(cell))

    def render_row(values: list[str]) -> str:
        padded = [value.ljust(widths[idx]) for idx, value in enumerate(values)]
        return "| " + " | ".join(padded) + " |"

    separator = ["-" * width for width in widths]
    lines = [render_row(headers), render_row(separator)]
    lines.extend(render_row(row) for row in rows)
    return lines


def render_config_reference(manifest: dict | None = None) -> str:
    manifest = manifest or load_manifest()
    items = resolve_config_items(manifest)
    by_section: "OrderedDict[str, list[ConfigItem]]" = OrderedDict()
    for item in items:
        by_section.setdefault(item.section, []).append(item)

    lines = [
        "# Configuration Surface",
        "",
        "Generated from `config_surface.toml`. Do not edit this file manually.",
        "",
        "This reference is the repo-native source-of-truth view for the Unraid-exposed configuration surface. The pinned upstream `env.ts` schema, the CA template generator, and runtime drift checks all validate against the same manifest.",
        "",
        "## Runtime Mode Legend",
        "",
        "- `always`: valid for both the default bundled path and external-service deployments",
        "- `bundled-only`: only meaningful when the bundled AIO services stay enabled",
        "- `external-service`: override or compatibility field for external PostgreSQL, Redis, SMTP, or other externalized dependencies",
        "- `bootstrap-only`: only used during the optional first-run bootstrap flow",
        "",
    ]

    for section, section_items in by_section.items():
        headers = [
            "Config",
            "Type",
            "Mode",
            "Required",
            "Default / Behavior",
            "Description",
        ]
        rows: list[list[str]] = []
        for item in section_items:
            rows.append(
                [
                    _markdown_cell(_config_label(item)),
                    item.xml_type,
                    _markdown_cell(f"`{item.runtime_mode}`"),
                    "yes" if item.required else "no",
                    _markdown_cell(_default_behavior_summary(item)),
                    _markdown_cell(item.description),
                ]
            )

        lines.extend(
            [
                f"## {section}",
                "",
                *_render_markdown_table(headers, rows),
            ]
        )
        lines.append("")

    return "\n".join(lines)
