from __future__ import annotations

import os

import pytest

from tests.helpers import docker_available, run_command

IMAGE_TAG = "infisical-aio:pytest"
pytestmark = pytest.mark.extended_integration


def test_runtime_matrix_script_exercises_supported_external_modes() -> None:
    if not docker_available():
        pytest.skip("Docker is unavailable; integration tests require Docker/OrbStack.")
    if os.environ.get("INFISICAL_ENABLE_RUNTIME_MATRIX") != "1":
        pytest.skip(
            "Set INFISICAL_ENABLE_RUNTIME_MATRIX=1 to run the extended runtime matrix."
        )

    run_command(["docker", "build", "--platform", "linux/amd64", "-t", IMAGE_TAG, "."])
    run_command(["bash", "scripts/validate-runtime-matrix.sh", IMAGE_TAG])
