# xlings Docker image
#
# Build:
#   docker build -t xlings-docker:dev .
#
# The xlings Linux client is a static-musl binary. The base image only provides
# the glibc userland that indexed packages expect, plus the tools a developer
# wants in an interactive container.

ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG XLINGS_VERSION=2026.10.26.1
ARG XLINGS_DOWNLOAD_BASE=https://github.com/openxlings/xlings/releases/download
ARG XLINGS_DEFAULT_MIRROR=GLOBAL
ARG XLINGS_PACKAGES=""
ARG DEV_UID=1000
ARG DEV_GID=1000
ARG TARGETARCH

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        bash-completion \
        bzip2 \
        ca-certificates \
        curl \
        git \
        less \
        openssh-client \
        procps \
        sudo \
        unzip \
        vim-tiny \
        xz-utils \
        zip \
    && rm -rf /var/lib/apt/lists/*

# A predictable uid/gid (1000 by default) keeps bind-mounted project files
# owned by the host user. Ubuntu 24.04 base images already carry a uid 1000
# account, so replace it instead of failing on a duplicate id.
RUN set -eux; \
    if getent passwd "${DEV_UID}" >/dev/null; then \
        userdel -r "$(getent passwd "${DEV_UID}" | cut -d: -f1)" 2>/dev/null || true; \
    fi; \
    if getent group "${DEV_GID}" >/dev/null; then \
        groupdel "$(getent group "${DEV_GID}" | cut -d: -f1)" 2>/dev/null || true; \
    fi; \
    groupadd --gid "${DEV_GID}" dev; \
    useradd --uid "${DEV_UID}" --gid dev --create-home --shell /bin/bash dev; \
    echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev; \
    chmod 0440 /etc/sudoers.d/dev; \
    mkdir -p /workspace; \
    chown dev:dev /workspace

COPY scripts/install-xlings.sh /usr/local/lib/xlings-docker/install-xlings.sh
COPY LICENSE /usr/share/doc/xlings-docker/LICENSE
COPY third_party/xlings-LICENSE /usr/share/doc/xlings/LICENSE

RUN chmod 0755 /usr/local/lib/xlings-docker/install-xlings.sh \
    && XLINGS_VERSION="${XLINGS_VERSION}" \
       XLINGS_DOWNLOAD_BASE="${XLINGS_DOWNLOAD_BASE}" \
       XLINGS_RELEASE_MIRROR="${XLINGS_DEFAULT_MIRROR}" \
       XLINGS_MIRROR="${XLINGS_DEFAULT_MIRROR}" \
       TARGETARCH="${TARGETARCH}" \
       XLINGS_INSTALL_USER=dev \
       /usr/local/lib/xlings-docker/install-xlings.sh

# Keep the entrypoint in its own layer: editing it must not re-run the install.
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

ENV HOME=/home/dev \
    PATH=/home/dev/.xlings/subos/current/bin:/home/dev/.xlings/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    GIT_TERMINAL_PROMPT=0

# Optional packages baked into a derived image or a team base image.
# hadolint ignore=DL3066
USER dev
RUN if [ -n "${XLINGS_PACKAGES}" ]; then \
        xlings install -y -g ${XLINGS_PACKAGES}; \
    fi
# hadolint ignore=DL3066
USER root

# A snapshot of the initialized home. An empty bind mount over
# /home/dev/.xlings hides the home baked into the image; the entrypoint
# restores this snapshot offline instead of re-running `self install`.
RUN tar -czf /opt/xlings/home.tar.gz \
        --exclude=./.xlings.lock \
        -C /home/dev/.xlings . \
    && chmod 0644 /opt/xlings/home.tar.gz

LABEL org.opencontainers.image.title="xlings" \
      org.opencontainers.image.description="xlings package manager in a container: interactive install, remove and run, with project-level .xlings.json support." \
      org.opencontainers.image.url="https://github.com/openxlings/xlings" \
      org.opencontainers.image.version="${XLINGS_VERSION}" \
      org.opencontainers.image.licenses="MIT AND Apache-2.0" \
      org.opencontainers.image.base.name="${BASE_IMAGE}"

WORKDIR /workspace
# hadolint ignore=DL3066
USER dev

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash"]
