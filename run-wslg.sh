#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found." >&2
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

if [[ ! -d /mnt/wslg ]]; then
  echo "/mnt/wslg was not found. Run this script inside a WSL2 distro with WSLg enabled." >&2
  exit 1
fi

if [[ ! -e /dev/dxg ]]; then
  echo "/dev/dxg was not found. WSL GPU acceleration is not available in this distro." >&2
  exit 1
fi

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set. WSLg does not appear to be initialized." >&2
  exit 1
fi

if [[ ! -d /usr/lib/wsl/lib ]]; then
  echo "/usr/lib/wsl/lib was not found. WSL GPU userspace libraries are unavailable." >&2
  exit 1
fi

mkdir -p workspace

COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.wslg.yml)
GPU_COMPOSE_FILE="$(mktemp /tmp/docker-gcoordinator-wslg.XXXXXX.yml)"

cleanup_gpu_compose_file() {
  if [[ -n "${GPU_COMPOSE_FILE:-}" && -f "$GPU_COMPOSE_FILE" ]]; then
    rm -f "$GPU_COMPOSE_FILE"
  fi
}
trap cleanup_gpu_compose_file EXIT

{
  printf '%s\n' 'services:'
  printf '%s\n' '  gcoordinator:'
  printf '%s\n' '    devices:'
  printf '%s\n' '      - /dev/dxg:/dev/dxg'

  DXG_GROUP_ID="$(stat -c '%g' /dev/dxg)"
  if [[ -n "$DXG_GROUP_ID" ]]; then
    printf '%s\n' '    group_add:'
    printf '      - "%s"\n' "$DXG_GROUP_ID"
  fi
} > "$GPU_COMPOSE_FILE"

COMPOSE_FILES+=(-f "$GPU_COMPOSE_FILE")

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  export WAYLAND_DISPLAY=wayland-0
fi

export XDG_RUNTIME_DIR=/tmp/runtime-gcoordinator

if [[ -z "${PULSE_SERVER:-}" ]]; then
  export PULSE_SERVER=/mnt/wslg/PulseServer
fi

echo "WSLg enabled: DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "GPU enabled: /dev/dxg will be passed to the container."

env UID="$(id -u)" GID="$(id -g)" \
  "${COMPOSE_CMD[@]}" "${COMPOSE_FILES[@]}" run --rm gcoordinator
