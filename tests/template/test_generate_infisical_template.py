from __future__ import annotations

import sys

import defusedxml.ElementTree as ET

from tests.conftest import REPO_ROOT
from tests.helpers import run_command


def test_generated_infisical_template_is_current() -> None:
    result = run_command(
        [sys.executable, "scripts/generate_infisical_template.py", "--check"],
        cwd=REPO_ROOT,
    )
    assert "matches the generated template" in result.stdout  # nosec B101


def test_mailpit_ui_port_is_opt_in() -> None:
    root = ET.parse(REPO_ROOT / "infisical-aio.xml").getroot()
    mailpit_publish = None
    for port in root.findall("./Networking/Publish/Port"):
        if (port.findtext("ContainerPort") or "").strip() == "8025":
            mailpit_publish = port
            break

    assert mailpit_publish is not None  # nosec B101
    assert (mailpit_publish.findtext("HostPort") or "").strip() == ""  # nosec B101

    mailpit_config = root.find("./Config[@Name='Local Mail Inbox Port']")
    assert mailpit_config is not None  # nosec B101
    assert mailpit_config.attrib["Default"] == ""  # nosec B101
    assert mailpit_config.attrib["Display"] == "advanced"  # nosec B101
    assert (mailpit_config.text or "").strip() == ""  # nosec B101


def test_ca_metadata_uses_current_categories_and_discovery_fields() -> None:
    root = ET.parse(REPO_ROOT / "infisical-aio.xml").getroot()

    assert root.findtext("Category") == "Security Tools:Utilities"  # nosec B101
    assert (  # nosec B101
        root.findtext("ReadMe") == "https://github.com/JSONbored/infisical-aio#readme"
    )
    assert [s.text for s in root.findall("Screenshot")] == [  # nosec B101
        "https://raw.githubusercontent.com/JSONbored/awesome-unraid/main/screenshots/infisical-aio/01-login.png",
        "https://raw.githubusercontent.com/JSONbored/awesome-unraid/main/screenshots/infisical-aio/02-dashboard.png",
        "https://raw.githubusercontent.com/JSONbored/awesome-unraid/main/screenshots/infisical-aio/03-project.png",
    ]
