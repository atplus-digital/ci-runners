ARG RUNNER_IMAGE
FROM ${RUNNER_IMAGE}
USER root
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ci-browser/browsers
WORKDIR /opt/ci-browser
ARG PLAYWRIGHT_VERSION=1.62.1
RUN printf '{"private":true,"dependencies":{"playwright":"%s"}}\n' "$PLAYWRIGHT_VERSION" > package.json \
    && bun install \
    && bunx playwright install --with-deps chromium \
    && printf '%s\n' "$PLAYWRIGHT_VERSION" > playwright-version \
    && chmod -R a+rX /opt/ci-browser
USER runner
WORKDIR /home/runner
