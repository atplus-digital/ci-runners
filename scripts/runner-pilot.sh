#!/usr/bin/env bash
set -euo pipefail

test -n "${RUNNER_TEMP:?}"
test -n "${GITHUB_STEP_SUMMARY:?}"
mkdir -p "$RUNNER_TEMP/runner-pilot-cache"
printf 'Public toolchain pilot cache v1\n' > "$RUNNER_TEMP/runner-pilot-cache/sentinel.txt"

{
  printf '# Runner pilot\n\n'
  printf 'Runner: `%s` · cache hit: `%s`\n\n' "$PILOT_RUNNER" "${PILOT_CACHE_HIT:-false}"
  printf '```text\n'
  node --version
  python3 --version
  docker version --format 'Docker server {{.Server.Version}}'
  docker info --format 'Docker security {{json .SecurityOptions}}'
  printf '```\n'
} >> "$GITHUB_STEP_SUMMARY"

node <<'JS' | tee -a "$GITHUB_STEP_SUMMARY"
const crypto = require('node:crypto');
const os = require('node:os');
const samples = [];
for (let i = 0; i < 5; i++) {
  const start = performance.now();
  crypto.pbkdf2Sync('public-pilot', 'public-salt', 200000, 32, 'sha256');
  samples.push(Math.round((performance.now() - start) * 100) / 100);
}
console.log('\n```json\n' + JSON.stringify({
  node: process.version, arch: process.arch, cpus: os.availableParallelism(),
  cpuModel: os.cpus()[0]?.model, memoryGiB: Math.round(os.totalmem() / 2 ** 30),
  pbkdf2Milliseconds: samples,
}, null, 2) + '\n```');
JS

python3 <<'PY' | tee -a "$GITHUB_STEP_SUMMARY"
import json, os, tempfile, time
from pathlib import Path
size = 128 * 1024 * 1024
start = time.monotonic()
with tempfile.TemporaryFile(dir=os.environ['RUNNER_TEMP']) as target:
    for _ in range(128):
        target.write(os.urandom(1024 * 1024))
    target.flush()
    os.fsync(target.fileno())
seconds = time.monotonic() - start
limits = {name: Path('/sys/fs/cgroup', name).read_text().strip() for name in ('cpu.max', 'memory.max') if Path('/sys/fs/cgroup', name).is_file()}
print('\n```json\n' + json.dumps({'writeAndFsyncMiB': 128, 'seconds': round(seconds, 3), 'MiBPerSecond': round(size / 2**20 / seconds, 1), 'cgroupLimits': limits}) + '\n```')
PY

{
  printf '\n```text\n'
  curl --fail --silent --show-error --location --connect-timeout 10 --max-time 30 \
    --output /dev/null \
    --write-out 'npm dns=%{time_namelookup}s tcp=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s bytes=%{size_download} speed=%{speed_download}B/s\n' \
    https://registry.npmjs.org/typescript/-/typescript-5.8.3.tgz
  printf '```\n'
} >> "$GITHUB_STEP_SUMMARY"

docker run --rm --pull=always --network none --cpus=1 --memory=128m \
  --cap-drop ALL --security-opt no-new-privileges \
  alpine:3.22 sh -ec 'test -r /etc/os-release; grep "^Seccomp:" /proc/self/status; cat /proc/self/attr/current'
