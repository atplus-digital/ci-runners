ARG RUNNER_IMAGE
FROM ${RUNNER_IMAGE}
USER root
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ci-browser/browsers
WORKDIR /opt/ci-browser
ARG PLAYWRIGHT_VERSION=1.62.1
ARG VISION_PLAYWRIGHT_VERSION=1.61.1
RUN printf '{"private":true,"dependencies":{"playwright":"%s"}}\n' "$PLAYWRIGHT_VERSION" > package.json \
    && bun install \
    && bunx playwright install --with-deps chromium \
    && printf '%s\n' "$PLAYWRIGHT_VERSION" > playwright-version \
    && mkdir -p "/opt/ci-browser/versions/$VISION_PLAYWRIGHT_VERSION" \
    && cd "/opt/ci-browser/versions/$VISION_PLAYWRIGHT_VERSION" \
    && printf '{"private":true,"dependencies":{"playwright":"%s"}}\n' "$VISION_PLAYWRIGHT_VERSION" > package.json \
    && bun install && bunx playwright install chromium \
    && chmod -R a+rX /opt/ci-browser \
    && chown -R runner:runner /opt/ci-browser/browsers
USER runner
WORKDIR /home/runner
