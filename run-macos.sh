#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1 &&
  [[ -x /Applications/Docker.app/Contents/Resources/bin/docker ]]; then
  export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found. Install and start Docker Desktop." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  if [[ ! -d /Applications/Docker.app ]]; then
    echo "Docker Desktop is not installed. Run ./setup-macos.sh first." >&2
    exit 1
  fi

  echo "Starting Docker Desktop..."
  open -a Docker

  echo "Waiting for Docker Desktop to become ready..."
  for _ in {1..120}; do
    if docker info >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! docker info >/dev/null 2>&1; then
    echo "Docker Desktop did not become ready within 120 seconds." >&2
    echo "Complete any first-run dialogs and retry." >&2
    exit 1
  fi
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is not available. Update Docker Desktop." >&2
  exit 1
fi

mkdir -p workspace
export MACOS_VNC_PORT="${MACOS_VNC_PORT:-5900}"
COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.macos.yml)

CONTAINER_ID="$(
  env UID="$(id -u)" GID="$(id -g)" MACOS_VNC_PORT="$MACOS_VNC_PORT" \
    docker compose "${COMPOSE_FILES[@]}" run --rm --detach --service-ports gcoordinator
)"

cleanup() {
  docker rm -f "$CONTAINER_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "Waiting for the VNC display on port $MACOS_VNC_PORT..."
VNC_READY=0
for _ in {1..120}; do
  if nc -z 127.0.0.1 "$MACOS_VNC_PORT" >/dev/null 2>&1; then
    VNC_READY=1
    break
  fi
  if ! docker inspect "$CONTAINER_ID" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if [[ "$VNC_READY" != "1" ]]; then
  docker logs "$CONTAINER_ID" >&2 || true
  echo "The VNC display did not become ready." >&2
  exit 1
fi

echo "Opening macOS Screen Sharing..."
open "vnc://127.0.0.1:$MACOS_VNC_PORT"
docker logs --follow "$CONTAINER_ID"
