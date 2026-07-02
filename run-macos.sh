#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found. Install and start Docker Desktop." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker Desktop is not running." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is not available. Update Docker Desktop." >&2
  exit 1
fi

XHOST=""
if command -v xhost >/dev/null 2>&1; then
  XHOST="$(command -v xhost)"
elif [[ -x /opt/X11/bin/xhost ]]; then
  XHOST=/opt/X11/bin/xhost
else
  echo "xhost was not found. Install XQuartz, start it, and enable network client connections." >&2
  exit 1
fi

if ! pgrep -x Xquartz >/dev/null 2>&1; then
  echo "XQuartz is not running. Start XQuartz before running this script." >&2
  exit 1
fi

XHOST_GRANTED=0
if ! "$XHOST" 2>/dev/null | grep -Eq '(^|[[:space:]])(INET:)?localhost([[:space:]]|$)'; then
  if ! "$XHOST" +localhost >/dev/null 2>&1; then
    echo "Could not grant localhost access to XQuartz." >&2
    echo "In XQuartz Settings > Security, enable 'Allow connections from network clients', restart XQuartz, and retry." >&2
    exit 1
  fi
  XHOST_GRANTED=1
fi

cleanup() {
  if [[ "$XHOST_GRANTED" == "1" ]]; then
    "$XHOST" -localhost >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p workspace
export MACOS_DISPLAY="${MACOS_DISPLAY:-host.docker.internal:0}"

echo "XQuartz enabled: DISPLAY=$MACOS_DISPLAY"
env UID="$(id -u)" GID="$(id -g)" \
  docker compose -f docker-compose.yml -f docker-compose.macos.yml run --rm gcoordinator
