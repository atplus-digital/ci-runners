#!/usr/bin/env bash
set -euo pipefail
test "$(id -un)" = runner
test "$(node -p 'process.versions.node.split(".")[0]')" = 22
python3 -c 'import sys, ssl, sqlite3, bz2, lzma, ctypes; assert sys.version_info[:2] == (3, 12)'
python3 -m venv /tmp/ci-python-smoke
/tmp/ci-python-smoke/bin/python -m pip --version
test "$(bun --version)" = 1.4.0
command -v bunx
gh --version
pwsh -NoLogo -NoProfile -Command 'if ($PSVersionTable.PSVersion.Major -ne 7) { exit 1 }'
ffmpeg -version >/dev/null
docker --version
docker compose version
command -v gcc xvfb-run jq git
node_version="$(node -p process.versions.node)"
python_version="$(python3 -c 'import platform; print(platform.python_version())')"
test -f "$RUNNER_TOOL_CACHE/node/$node_version/x64.complete"
test -f "$RUNNER_TOOL_CACHE/Python/$python_version/x64.complete"
