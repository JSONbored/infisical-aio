from __future__ import annotations

import os

import pytest

from tests.helpers import docker_available, ensure_pytest_image, run_command

IMAGE_TAG = "infisical-aio:pytest"
pytestmark = pytest.mark.extended_integration

RUNTIME_MATRIX_MODES = (
    "bundled",
    "manual-secret-overrides",
    "bootstrap",
    "external-postgres-uri",
    "external-postgres-fields",
    "external-redis-url",
    "external-redis-sentinel",
    "external-redis-cluster",
    "redis-tls-private-ca",
    "external-smtp",
    "metrics",
)


@pytest.mark.parametrize("mode", RUNTIME_MATRIX_MODES)
def test_runtime_matrix_mode(mode: str) -> None:
    if not docker_available():
        pytest.skip("Docker is unavailable; integration tests require Docker/OrbStack.")
    if os.environ.get("INFISICAL_ENABLE_RUNTIME_MATRIX") != "1":
        pytest.skip(
            "Set INFISICAL_ENABLE_RUNTIME_MATRIX=1 to run the extended runtime matrix."
        )

    ensure_pytest_image(IMAGE_TAG)
    run_command(["bash", "scripts/validate-runtime-matrix.sh", IMAGE_TAG, mode])
