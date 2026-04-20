# syntax=docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
# checkov:skip=CKV_DOCKER_3: s6-overlay requires root init so bundled services can prepare state before dropping privileges
ARG UPSTREAM_VERSION=v0.159.18
ARG UPSTREAM_IMAGE_DIGEST=sha256:2b3d18c8bf08a7113afed9de3048d80c505d5e85f8183ea27830362a8ac33c1b
FROM infisical/infisical:${UPSTREAM_VERSION}@${UPSTREAM_IMAGE_DIGEST}

ARG S6_OVERLAY_VERSION=3.2.1.0
ARG INTERNAL_POSTGRESQL_MAJOR=16
ARG INTERNAL_REDIS_MAJOR=7
ARG TARGETARCH

LABEL org.opencontainers.image.source="https://github.com/JSONbored/infisical-aio" \
      org.opencontainers.image.title="infisical-aio" \
      org.opencontainers.image.description="Infisical packaged as a single-container Unraid AIO image with bundled PostgreSQL and Redis defaults"

USER root
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get -y dist-upgrade && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    jq \
    xz-utils && \
    install -d -m 0755 /etc/apt/keyrings /var/lib/apt/lists/partial && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt trixie-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /etc/apt/keyrings/redis.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/redis.gpg] https://packages.redis.io/deb trixie main" > /etc/apt/sources.list.d/redis.list && \
    apt-get update && \
    POSTGRESQL_PACKAGE_VERSION="$(apt-cache madison postgresql-${INTERNAL_POSTGRESQL_MAJOR} | awk 'NR==1 {print $3}')" && \
    REDIS_PACKAGE_VERSION="$(apt-cache madison redis-server | grep -m1 "6:${INTERNAL_REDIS_MAJOR}\\." | awk '{print $3}')" && \
    test -n "${POSTGRESQL_PACKAGE_VERSION}" && test -n "${REDIS_PACKAGE_VERSION}" && \
    apt-get install -y --no-install-recommends \
      "postgresql-${INTERNAL_POSTGRESQL_MAJOR}=${POSTGRESQL_PACKAGE_VERSION}" \
      "postgresql-client-${INTERNAL_POSTGRESQL_MAJOR}=${POSTGRESQL_PACKAGE_VERSION}" \
      "redis-server=${REDIS_PACKAGE_VERSION}" \
      "redis-tools=${REDIS_PACKAGE_VERSION}" && \
    curl -L -o /tmp/s6-overlay-noarch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" && \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    case "${TARGETARCH}" in \
      amd64) s6_arch="x86_64" ;; \
      arm64) s6_arch="aarch64" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    curl -L -o /tmp/s6-overlay-arch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${s6_arch}.tar.xz" && \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz && \
    mkdir -p /config/aio /data/postgres /data/redis /run/postgresql && \
    chown -R postgres:postgres /data/postgres /run/postgresql && \
    chown -R redis:redis /data/redis && \
    chmod 700 /data/postgres /data/redis && \
    rm -rf /tmp/* /var/lib/apt/lists/*

COPY rootfs/ /

RUN find /etc/cont-init.d -type f -exec chmod +x {} \; && \
    find /etc/services.d -type f -name run -exec chmod +x {} \; && \
    find /usr/local/bin -type f -exec chmod +x {} \;

VOLUME ["/config", "/data"]
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8080/api/status >/dev/null || exit 1

ENTRYPOINT ["/init"]
