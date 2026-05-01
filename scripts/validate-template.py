#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import subprocess  # nosec B404
import sys
import xml.etree.ElementTree as ET  # nosec B405 - this validator reads a trusted local repository XML file only
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_TEXT_FIELDS = (
    "Support",
    "Project",
    "Overview",
    "Category",
    "TemplateURL",
    "Icon",
    "Changes",
)

GENERATED_CHANGELOG_NOTE = (
    "Generated from CHANGELOG.md during release preparation. Do not edit manually."
)
GENERATED_CHANGELOG_BULLET = f"- {GENERATED_CHANGELOG_NOTE}"
CHANGELOG_HEADER_PATTERN = re.compile(r"^### \d{4}-\d{2}-\d{2}$")
LEGACY_CHANGELOG_MARKERS = (
    "[b]Latest release[/b]",
    "GitHub Releases",
    "Full changelog and release notes:",
)


def run_common_template_validation() -> int:
    candidates = []
    explicit = os.environ.get("AIO_FLEET_MANIFEST", "").strip()
    if explicit:
        candidates.append(Path(explicit))
    candidates.extend(
        [
            ROOT / ".aio-fleet" / "fleet.yml",
            ROOT.parent / "aio-fleet" / "fleet.yml",
        ]
    )
    manifest = next((candidate for candidate in candidates if candidate.exists()), None)
    if manifest is None:
        print(
            "warning: aio-fleet manifest not found; skipping common template validation",
            file=sys.stderr,
        )
        return 0

    env = os.environ.copy()
    fleet_src = manifest.parent / "src"
    if fleet_src.exists():
        existing = env.get("PYTHONPATH", "")
        env["PYTHONPATH"] = (
            f"{fleet_src}{os.pathsep}{existing}" if existing else str(fleet_src)
        )
    python = sys.executable
    fleet_python = manifest.parent / ".venv" / "bin" / "python"
    if fleet_python.exists():
        python = str(fleet_python)

    result = subprocess.run(  # nosec B603
        [
            python,
            "-m",
            "aio_fleet.cli",
            "--manifest",
            str(manifest),
            "validate-template-common",
            "--repo",
            ROOT.name,
            "--repo-path",
            str(ROOT),
        ],
        check=False,
        text=True,
        capture_output=True,
        env=env,
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    return result.returncode


def resolve_template_path() -> Path:
    explicit = os.environ.get("TEMPLATE_XML", "").strip()
    if explicit:
        return ROOT / explicit

    repo_xml = ROOT / f"{ROOT.name}.xml"
    if repo_xml.exists():
        return repo_xml

    xml_files = sorted(ROOT.glob("*.xml"))
    if len(xml_files) == 1:
        return xml_files[0]

    return ROOT / "template-aio.xml"


def is_placeholder_template(xml_path: Path) -> bool:
    return xml_path.name == "template-aio.xml" or ROOT.name == "unraid-aio-template"


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def validate_changes(xml_name: str, changes: str) -> int:
    for marker in LEGACY_CHANGELOG_MARKERS:
        if marker in changes:
            return fail(
                f"{xml_name} <Changes> still uses the legacy release-link format: {marker}"
            )

    lines = [line.strip() for line in changes.splitlines() if line.strip()]
    if len(lines) < 3:
        return fail(
            f"{xml_name} <Changes> must include a date heading, the generated note, and at least one bullet"
        )
    if not CHANGELOG_HEADER_PATTERN.fullmatch(lines[0]):
        return fail(f"{xml_name} <Changes> must start with '### YYYY-MM-DD'")
    if lines[1] != GENERATED_CHANGELOG_BULLET:
        return fail(
            f"{xml_name} <Changes> second line should be '{GENERATED_CHANGELOG_BULLET}'"
        )
    invalid_lines = [line for line in lines[1:] if not line.startswith("- ")]
    if invalid_lines:
        return fail(
            f"{xml_name} <Changes> must use bullet lines after the heading; found {invalid_lines[0]!r}"
        )
    return 0


def main() -> int:
    common_status = run_common_template_validation()
    if common_status:
        return common_status

    xml_path = resolve_template_path()
    if not xml_path.exists():
        return fail(f"Template XML not found: {xml_path}")

    # nosec B314 - trusted local template file only
    tree = ET.parse(xml_path)  # nosec B314 - trusted local template file only
    root = tree.getroot()

    for field in REQUIRED_TEXT_FIELDS:
        value = (root.findtext(field) or "").strip()
        if not value:
            return fail(f"{xml_path.name} is missing a non-empty <{field}> field")

    template_url = (root.findtext("TemplateURL") or "").strip()
    if "awesome-unraid/main/" not in template_url:
        return fail(
            f"{xml_path.name} TemplateURL should point at raw awesome-unraid/main XML"
        )

    icon_url = (root.findtext("Icon") or "").strip()
    if "awesome-unraid/main/icons/" not in icon_url:
        return fail(
            f"{xml_path.name} Icon should point at raw awesome-unraid/main/icons asset"
        )

    changes = (root.findtext("Changes") or "").strip()
    if not changes:
        return fail(f"{xml_path.name} is missing a non-empty <Changes> field")
    changes_status = validate_changes(xml_path.name, changes)
    if changes_status:
        return changes_status

    invalid_option_configs: list[str] = []
    invalid_pipe_configs: list[str] = []
    for config in root.findall(".//Config"):
        name = config.attrib.get("Name", config.attrib.get("Target", "<unnamed>"))
        if config.findall("Option"):
            invalid_option_configs.append(name)

        default = config.attrib.get("Default", "")
        if "|" not in default:
            continue

        allowed_values = default.split("|")
        if any(value == "" for value in allowed_values):
            invalid_pipe_configs.append(
                f"{name} (allowed={allowed_values!r}, empty pipe options are not allowed)"
            )
            continue

        selected_value = (config.text or "").strip()
        if selected_value not in allowed_values:
            invalid_pipe_configs.append(
                f"{name} (selected={selected_value!r}, allowed={allowed_values!r})"
            )

    if invalid_option_configs:
        print(
            f"{xml_path.name} uses nested <Option> tags, which are not allowed by the catalog-safe template format:",
            file=sys.stderr,
        )
        for name in invalid_option_configs:
            print(f"  - {name}", file=sys.stderr)
        return 1

    if invalid_pipe_configs:
        print(
            f"{xml_path.name} has pipe-delimited defaults whose selected value is not one of the allowed options:",
            file=sys.stderr,
        )
        for detail in invalid_pipe_configs:
            print(f"  - {detail}", file=sys.stderr)
        return 1

    print(f"{xml_path.name} parsed successfully and passed catalog-safe validation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
