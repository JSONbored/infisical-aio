#!/usr/bin/env python3
from __future__ import annotations

import os
import sys

# nosec B405 - this validator reads a trusted local repository XML file only
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

PLACEHOLDER_RELEASE_URL = "https://github.com/JSONbored/yourapp-aio/releases"

REQUIRED_TEXT_FIELDS = (
    "Support",
    "Project",
    "Overview",
    "Category",
    "TemplateURL",
    "Icon",
    "Changes",
)


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


def main() -> int:
    xml_path = resolve_template_path()
    if not xml_path.exists():
        return fail(f"Template XML not found: {xml_path}")

    # nosec B314 - trusted local template file only
    tree = ET.parse(xml_path)
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
    if not is_placeholder_template(xml_path):
        expected_release_url = f"https://github.com/JSONbored/{ROOT.name}/releases"
        if expected_release_url not in changes:
            return fail(
                f"{xml_path.name} <Changes> should include the canonical GitHub releases URL: "
                f"{expected_release_url}"
            )
    else:
        template_release_url = f"https://github.com/JSONbored/{ROOT.name}/releases"
        if PLACEHOLDER_RELEASE_URL not in changes and template_release_url not in changes:
            return fail(
                f"{xml_path.name} placeholder <Changes> block should include either "
                f"{PLACEHOLDER_RELEASE_URL} or {template_release_url}"
            )

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
