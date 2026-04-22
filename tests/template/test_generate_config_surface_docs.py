from __future__ import annotations

import sys

from tests.conftest import REPO_ROOT
from tests.helpers import run_command


def test_generated_configuration_reference_is_current() -> None:
    result = run_command(
        [sys.executable, "scripts/generate_config_surface_docs.py", "--check"],
        cwd=REPO_ROOT,
    )
    assert (
        "matches the generated configuration reference" in result.stdout
    )  # nosec B101
