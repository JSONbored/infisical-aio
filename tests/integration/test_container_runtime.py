from __future__ import annotations

import time
import uuid
from contextlib import contextmanager

import pytest

from tests.helpers import (
    container_path_exists,
    docker_available,
    docker_volume,
    ensure_pytest_image,
    read_container_file,
    reserve_host_port,
    run_command,
)

IMAGE_TAG = "infisical-aio:pytest"
pytestmark = pytest.mark.integration


def logs(name: str) -> str:
    result = run_command(["docker", "logs", name], check=False)
    return result.stdout + result.stderr


def wait_for_http(name: str, host_port: int, timeout: int = 300) -> None:
    deadline = time.time() + timeout
    url = f"http://127.0.0.1:{host_port}/api/status"

    while time.time() < deadline:
        status = run_command(
            ["docker", "inspect", "-f", "{{.State.Status}}", name],
            check=False,
        ).stdout.strip()
        if status != "running":
            raise AssertionError(f"{name} stopped before becoming ready.\n{logs(name)}")

        if run_command(["curl", "-fsS", url], check=False).returncode == 0:
            return
        time.sleep(2)

    raise AssertionError(f"{name} did not become ready.\n{logs(name)}")


@contextmanager
def container(config_volume: str, data_volume: str):
    name = f"infisical-aio-pytest-{uuid.uuid4().hex[:10]}"
    host_port = reserve_host_port()
    command = [
        "docker",
        "run",
        "-d",
        "--platform",
        "linux/amd64",
        "--name",
        name,
        "-p",
        f"{host_port}:8080",
        "-e",
        f"SITE_URL=http://127.0.0.1:{host_port}",
        "-v",
        f"{config_volume}:/config",
        "-v",
        f"{data_volume}:/data",
        IMAGE_TAG,
    ]
    run_command(command)
    try:
        yield name, host_port
    finally:
        run_command(["docker", "rm", "-f", name], check=False)


@pytest.fixture(scope="session", autouse=True)
def build_image() -> None:
    if not docker_available():
        pytest.skip("Docker is unavailable; integration tests require Docker/OrbStack.")
    ensure_pytest_image(IMAGE_TAG)


def test_happy_path_boot_and_restart_persists_generated_env() -> None:
    with (
        docker_volume("infisical-aio-config") as config_volume,
        docker_volume("infisical-aio-data") as data_volume,
    ):
        with container(config_volume, data_volume) as (name, host_port):
            wait_for_http(name, host_port)
            assert container_path_exists(
                name, "/config/aio/generated.env"
            )  # nosec B101
            generated_contents = read_container_file(name, "/config/aio/generated.env")
            assert "AIO_MAILPIT_UI_USERNAME=" in generated_contents  # nosec B101
            assert "AIO_MAILPIT_UI_PASSWORD=" in generated_contents  # nosec B101
            first_logs = logs(name)
            assert (
                "[infisical-aio] Timed out waiting for the Infisical API."
                not in first_logs
            )  # nosec B101
            assert (
                "[infisical-aio] Bootstrap request failed" not in first_logs
            )  # nosec B101

            run_command(["docker", "restart", name])
            wait_for_http(name, host_port)
            assert container_path_exists(
                name, "/config/aio/generated.env"
            )  # nosec B101
            second_contents = read_container_file(name, "/config/aio/generated.env")
            assert "AIO_MAILPIT_UI_USERNAME=" in second_contents  # nosec B101
            assert "AIO_MAILPIT_UI_PASSWORD=" in second_contents  # nosec B101
