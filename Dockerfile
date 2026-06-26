# syntax=docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
# checkov:skip=CKV_DOCKER_3: s6-overlay requires root init so bundled services can prepare state before dropping privileges
ARG UPSTREAM_VERSION=v0.161.8
ARG UPSTREAM_IMAGE_DIGEST=sha256:2b6d8b5fdaa8e22a485d0fefddbf37d15e4f8b16027333ee90653c3854aca5d0
ARG MAILPIT_VERSION=v1.30.2
ARG MAILPIT_IMAGE_DIGEST=sha256:37a38e48e9338cd7e89dfeb487f37b02ebfcd9cb23111bed2d345e79d37d6dd6
FROM jsonbored/aio-base:s6-3.2.1.0@sha256:07db479a01a95ba28480b4605f5d1cc8bedb574b77cf167ee46e29b9558fee90 AS aio-base

FROM infisical/infisical:${UPSTREAM_VERSION}@${UPSTREAM_IMAGE_DIGEST}

FROM axllent/mailpit:${MAILPIT_VERSION}@${MAILPIT_IMAGE_DIGEST} AS mailpit

FROM infisical/infisical:${UPSTREAM_VERSION}@${UPSTREAM_IMAGE_DIGEST}

ARG INTERNAL_POSTGRESQL_MAJOR=16
ARG INTERNAL_REDIS_MAJOR=7

LABEL org.opencontainers.image.source="https://github.com/JSONbored/infisical-aio" \
      org.opencontainers.image.title="infisical-aio" \
      org.opencontainers.image.description="Infisical packaged as a single-container Unraid AIO image with bundled PostgreSQL, Redis, and local Mailpit inbox defaults"

# checkov:skip=CKV_DOCKER_8: s6-overlay entrypoint must start as root so init scripts can prepare data directories and then drop privileges per service
# hadolint ignore=DL3002
USER root
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Shared, pinned s6-overlay from the fleet aio-base overlay.
COPY --from=aio-base /aio-overlay/ /

RUN aio-harden pre && \
    apt-get update && apt-get -y dist-upgrade && apt-get install -y --no-install-recommends \
    ca-certificates="$(apt-cache madison ca-certificates | awk 'NR==1 {print $3}')" \
    curl="$(apt-cache madison curl | awk 'NR==1 {print $3}')" \
    gnupg="$(apt-cache madison gnupg | awk 'NR==1 {print $3}')" \
    jq="$(apt-cache madison jq | awk 'NR==1 {print $3}')" \
    xz-utils="$(apt-cache madison xz-utils | awk 'NR==1 {print $3}')" && \
    install -d -m 0755 /etc/apt/keyrings /var/lib/apt/lists/partial && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt trixie-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /etc/apt/keyrings/redis.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/redis.gpg] https://packages.redis.io/deb trixie main" > /etc/apt/sources.list.d/redis.list && \
    apt-get update && \
    POSTGRESQL_PACKAGE_VERSION="$(apt-cache madison postgresql-${INTERNAL_POSTGRESQL_MAJOR} | awk 'NR==1 {print $3}')" && \
    REDIS_PACKAGE_VERSION="$(apt-cache madison redis-server | awk -v major="${INTERNAL_REDIS_MAJOR}" '$3 ~ "^6:" major "\\." { print $3; exit }')" && \
    test -n "${POSTGRESQL_PACKAGE_VERSION}" && test -n "${REDIS_PACKAGE_VERSION}" && \
    apt-get install -y --no-install-recommends \
      "postgresql-${INTERNAL_POSTGRESQL_MAJOR}=${POSTGRESQL_PACKAGE_VERSION}" \
      "postgresql-client-${INTERNAL_POSTGRESQL_MAJOR}=${POSTGRESQL_PACKAGE_VERSION}" \
      "redis-server=${REDIS_PACKAGE_VERSION}" \
      "redis-tools=${REDIS_PACKAGE_VERSION}" && \
    useradd --system --home-dir /var/lib/mailpit --create-home --shell /usr/sbin/nologin mailpit && \
    mkdir -p /config/aio /config/aio/mailpit /data/postgres /data/redis /data/mailpit /run/postgresql && \
    chown -R postgres:postgres /data/postgres /run/postgresql && \
    chown -R redis:redis /data/redis && \
    chown -R mailpit:mailpit /config/aio/mailpit /data/mailpit && \
    chmod 700 /config/aio/mailpit /data/postgres /data/redis /data/mailpit && \
    rm -rf /tmp/* /var/lib/apt/lists/*

COPY --from=mailpit /mailpit /usr/local/bin/mailpit
COPY rootfs/ /

RUN find /etc/cont-init.d -type f -exec chmod +x {} \; && \
    find /etc/services.d -type f -name run -exec chmod +x {} \; && \
    find /usr/local/bin -type f -exec chmod +x {} \;

VOLUME ["/config", "/data"]
EXPOSE 8080 8025 9464

ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=300000
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8080/api/status >/dev/null || exit 1

ENTRYPOINT ["/init"]
