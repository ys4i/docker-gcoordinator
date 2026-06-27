#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -d /mnt/wslg ]]; then
  echo "/mnt/wslg was not found. Run this inside WSL2 with WSLg enabled." >&2
  exit 1
fi

if [[ ! -e /dev/dxg ]]; then
  echo "/dev/dxg was not found. Install a WSL-compatible GPU driver and update WSL." >&2
  exit 1
fi

if [[ ! -d /usr/lib/wsl/lib ]]; then
  echo "/usr/lib/wsl/lib was not found. WSL GPU userspace libraries are unavailable." >&2
  exit 1
fi

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set. WSLg does not appear to be initialized." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found. Run setup-wsl-docker.sh first." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  sudo -n service docker start >/dev/null 2>&1 || true
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker Engine is not running. Run setup-wsl-docker.sh first." >&2
  exit 1
fi

COMPOSE_CMD=()
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif docker-compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "Docker Compose is not available inside WSL." >&2
  echo "Run setup-wsl-docker.sh to install the Docker Compose plugin." >&2
  exit 1
fi

mkdir -p workspace log

"${COMPOSE_CMD[@]}" -f docker-compose.yml -f docker-compose.wslg.yml build

echo "WSLg setup completed."
echo "Run: ./run-wslg.sh"
