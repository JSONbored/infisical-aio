from __future__ import annotations

import sys

from tests.conftest import REPO_ROOT
from tests.helpers import run_command


def test_generated_infisical_template_is_current() -> None:
    result = run_command(
        [sys.executable, "scripts/generate_infisical_template.py", "--check"],
        cwd=REPO_ROOT,
    )
    assert "matches the generated template" in result.stdout  # nosec B101
