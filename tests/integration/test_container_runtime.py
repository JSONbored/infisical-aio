from __future__ import annotations

import json
import secrets
import time
import uuid
from contextlib import closing, contextmanager
from http.client import HTTPConnection

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


def wait_for_exit(name: str, timeout: int = 120) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = run_command(
            ["docker", "inspect", "-f", "{{.State.Status}}", name],
            check=False,
        ).stdout.strip()
        if status == "exited":
            return
        if status and status != "running":
            raise AssertionError(
                f"{name} entered unexpected state {status}.\n{logs(name)}"
            )
        time.sleep(2)

    raise AssertionError(f"{name} did not exit.\n{logs(name)}")


def seed_postgres_major(data_volume: str, major: str) -> None:
    run_command(
        [
            "docker",
            "run",
            "--rm",
            "--platform",
            "linux/amd64",
            "-v",
            f"{data_volume}:/data",
            "--entrypoint",
            "sh",
            IMAGE_TAG,
            "-c",
            f"mkdir -p /data/postgres && printf '%s\\n' {major!r} >/data/postgres/PG_VERSION",
        ]
    )


@contextmanager
def container(config_volume: str, data_volume: str, image: str = IMAGE_TAG):
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
        f"127.0.0.1:{host_port}:8080",
        "-e",
        f"SITE_URL=http://127.0.0.1:{host_port}",
        "-v",
        f"{config_volume}:/config",
        "-v",
        f"{data_volume}:/data",
        image,
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


def test_existing_internal_postgres_major_mismatch_fails_fast() -> None:
    with (
        docker_volume("infisical-aio-config") as config_volume,
        docker_volume("infisical-aio-data") as data_volume,
    ):
        seed_postgres_major(data_volume, "15")

        with container(config_volume, data_volume) as (name, _host_port):
            wait_for_exit(name)
            output = logs(name)
            mismatch = (
                "Existing PostgreSQL data directory major (15) does not match "
                "bundled PostgreSQL major (16)."
            )
            migration_hint = "Please migrate your PostgreSQL data before upgrading"
            assert mismatch in output  # nosec B101
            assert migration_hint in output  # nosec B101


def test_upgrade_decrypts_secret_created_on_published_image() -> None:
    # The June stable image is the starting point for this upgrade.
    baseline = (
        "jsonbored/infisical-aio:v0.161.1-aio.1"
        "@sha256:34f7277cece4d002813984a0b4918d02e5fb77450a5726b5409b09dffe28c844"
    )
    value = secrets.token_hex(32)
    credentials = {
        "email": "upgrade@example.com",
        "password": secrets.token_urlsafe(32),
    }

    def api(port, method, path, body=None, token=None):
        headers = {"Content-Type": "application/json", "User-Agent": "aio-upgrade-test"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        with closing(HTTPConnection("127.0.0.1", port, timeout=30)) as connection:
            connection.request(
                method, path, json.dumps(body) if body else None, headers
            )
            response = connection.getresponse()
            if response.status != 200:
                raise AssertionError(f"{method} {path} returned HTTP {response.status}")
            return json.load(response)

    def login(port, organization_id):
        session = api(port, "POST", "/api/v3/auth/login", credentials)
        org_session = api(
            port,
            "POST",
            "/api/v3/auth/select-organization",
            {"organizationId": organization_id},
            session["accessToken"],
        )
        return org_session["token"]

    with (
        docker_volume("infisical-upgrade-config") as config_volume,
        docker_volume("infisical-upgrade-data") as data_volume,
    ):
        with container(config_volume, data_volume, baseline) as (name, port):
            wait_for_http(name, port)
            bootstrap = api(
                port,
                "POST",
                "/api/v1/admin/bootstrap",
                {**credentials, "organization": "Upgrade test"},
            )
            organization_id = bootstrap["organization"]["id"]
            token = login(port, organization_id)
            project = api(
                port, "POST", "/api/v1/projects", {"projectName": "Upgrade"}, token
            )["project"]
            environment = project["environments"][0]["slug"]
            path = "/api/v4/secrets/AIO_UPGRADE_TEST"
            location = {"projectId": project["id"], "environment": environment}
            created = api(port, "POST", path, {**location, "secretValue": value}, token)
            assert created["secret"]["secretValue"] == value  # nosec B101
            run_command(["docker", "stop", "-t", "45", name])

        with container(config_volume, data_volume) as (name, port):
            wait_for_http(name, port)
            query = f"{path}?projectId={project['id']}&environment={environment}"
            token = login(port, organization_id)
            restored = api(port, "GET", query, token=token)["secret"]
            assert restored["id"] == created["secret"]["id"]  # nosec B101
            assert restored["secretValue"] == value  # nosec B101
