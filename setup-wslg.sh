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
  echo "docker command not found. Enable Docker Desktop WSL integration or install Docker Engine in WSL." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is not available." >&2
  exit 1
fi

mkdir -p workspace log

docker compose -f docker-compose.yml -f docker-compose.wslg.yml build

echo "WSLg setup completed."
echo "Run: ./run-wslg.sh"
