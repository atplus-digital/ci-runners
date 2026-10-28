FROM node:22-bookworm AS node
FROM python:3.12-bookworm AS python
FROM oven/bun:1.4.0 AS bun
FROM docker:27-cli AS docker
FROM ghcr.io/actions/actions-runner@sha256:759a1d94a15b05941aba5196974ff43fe15b4cbba29b694b35cbc32a1166b232
USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl git jq unzip xz-utils zip rsync \
    ffmpeg liblapack3 libssl3t64 libffi8 libbz2-1.0 liblzma5 libsqlite3-0 \
    libreadline8t64 libncursesw6 libgdbm6t64 libexpat1 libicu74 \
    xvfb xauth libcap-dev meson ninja-build pkg-config libsecret-1-dev \
    fonts-liberation libasound2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 \
    libatspi2.0-0t64 libcups2t64 libdrm2 libgbm1 libgtk-3-0t64 libnotify4 \
    libnss3 libsecret-1-0 libxcomposite1 libxdamage1 libxfixes3 libxkbcommon0 \
    libxrandr2 libxss1 libxtst6 xdg-utils \
    && rm -rf /var/lib/apt/lists/*
COPY --from=python /usr/local/ /usr/local/
COPY --from=node /usr/local/ /opt/node/
COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun
COPY --from=docker /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker /usr/local/libexec/docker/cli-plugins/ /usr/local/lib/docker/cli-plugins/
ENV PATH=/opt/node/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache
RUN ldconfig \
    && ln -s /usr/local/bin/bun /usr/local/bin/bunx \
    && node_version="$(node -p process.versions.node)" \
    && python_version="$(python3 -c 'import platform; print(platform.python_version())')" \
    && mkdir -p "$RUNNER_TOOL_CACHE/node/$node_version" "$RUNNER_TOOL_CACHE/Python/$python_version" \
    && ln -s /opt/node "$RUNNER_TOOL_CACHE/node/$node_version/x64" \
    && ln -s /usr/local "$RUNNER_TOOL_CACHE/Python/$python_version/x64" \
    && touch "$RUNNER_TOOL_CACHE/node/$node_version/x64.complete" \
       "$RUNNER_TOOL_CACHE/Python/$python_version/x64.complete" \
    && chown -R runner:runner /opt/node /opt/hostedtoolcache /usr/local/lib/python3.12 /usr/local/bin
ARG GH_VERSION=2.96.0
ARG GH_SHA256=83d5c2ccad5498f58bf6368acb1ab32588cf43ab3a4b1c301bf36328b1c8bd60
ARG POWERSHELL_VERSION=7.6.4
ARG POWERSHELL_SHA256=4471b5a36bfe86ec7af8525d36bb1cacba0128e7aac22d05cc064bc00e604721
RUN curl -fsSL --connect-timeout 20 --max-time 180 --retry 3 \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tgz \
    && echo "$GH_SHA256  /tmp/gh.tgz" | sha256sum --check --strict \
    && tar -xzf /tmp/gh.tgz -C /tmp \
    && install "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && curl -fsSL --connect-timeout 20 --max-time 180 --retry 3 \
      "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell-${POWERSHELL_VERSION}-linux-x64.tar.gz" -o /tmp/pwsh.tgz \
    && echo "$POWERSHELL_SHA256  /tmp/pwsh.tgz" | sha256sum --check --strict \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar -xzf /tmp/pwsh.tgz -C /opt/microsoft/powershell/7 \
    && chmod 0755 /opt/microsoft/powershell/7/pwsh \
    && ln -s /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh \
    && rm -rf /tmp/gh* /tmp/pwsh.tgz
USER runner
WORKDIR /home/runner
