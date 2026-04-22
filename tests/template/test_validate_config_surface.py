from __future__ import annotations

import sys

from tests.conftest import REPO_ROOT
from tests.helpers import run_command


def test_validate_config_surface_script_passes() -> None:
    result = run_command(
        [sys.executable, "scripts/validate_config_surface.py"],
        cwd=REPO_ROOT,
    )
    assert (
        "config_surface.toml passed upstream, runtime, and bootstrap drift checks"
        in result.stdout
    )  # nosec B101
