FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG RUNNER_ARCH=X64
ARG WITH_CHROME=true
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git xz-utils unzip zip build-essential python3 meson ninja-build pkg-config libcap-dev \
    libsecret-1-dev xvfb xauth fonts-liberation libasound2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 \
    libatspi2.0-0t64 libcups2t64 libdrm2 libgbm1 libgtk-3-0t64 libnotify4 libnss3 libsecret-1-0 \
    libxcomposite1 libxdamage1 libxfixes3 libxkbcommon0 libxrandr2 libxss1 libxtst6 xdg-utils \
    && rm -rf /var/lib/apt/lists/*
# Ubuntu chromium-browser is a Snap bootstrap; use the official Chrome .deb.
RUN case "$WITH_CHROME" in \
      true) test "$RUNNER_ARCH" = X64 && test "$(dpkg --print-architecture)" = amd64 \
        && curl --proto '=https' --tlsv1.2 --connect-timeout 20 --fail --location --retry 3 \
          https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb --output /tmp/chrome.deb \
        && apt-get update && apt-get install -y --no-install-recommends /tmp/chrome.deb \
        && rm -rf /tmp/chrome.deb /var/lib/apt/lists/* ;; \
      false) ;; *) exit 1 ;; esac
# Same pinned non-setuid provider as setup-governed-workload. No host AppArmor reload.
# The Ubuntu archive (already reachable for apt) serves the byte-identical upstream tarball; GitHub release assets
# time out from the self-hosted cluster. The pinned sha256 decides, whatever the mirror.
RUN mkdir /tmp/bwrap-build && cd /tmp/bwrap-build \
    && for url in https://archive.ubuntu.com/ubuntu/pool/main/b/bubblewrap/bubblewrap_0.11.0.orig.tar.xz \
        https://github.com/containers/bubblewrap/releases/download/v0.11.0/bubblewrap-0.11.0.tar.xz; do \
      curl --proto '=https' --tlsv1.2 --connect-timeout 20 --max-time 120 --fail --location --retry 3 --retry-all-errors \
        "$url" --output source.tar.xz && break; \
    done \
    && echo '988fd6b232dafa04b8b8198723efeaccdb3c6aa9c1c7936219d5791a8b7a8646  source.tar.xz' | sha256sum --check --strict \
    && tar --extract --xz --file source.tar.xz \
    && meson setup build bubblewrap-0.11.0 -Dtests=false -Dman=disabled -Dbash_completion=disabled -Dzsh_completion=disabled -Dselinux=disabled \
    && meson compile -C build \
    && install --owner=root --group=root --mode=0755 build/bwrap /usr/bin/bwrap \
    && test "$(stat -c '%u:%g:%a' /usr/bin/bwrap)" = 0:0:755 \
    && test "$(/usr/bin/bwrap --version)" = 'bubblewrap 0.11.0' \
    && cd / && rm -rf /tmp/bwrap-build
