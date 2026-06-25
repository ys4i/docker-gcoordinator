#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is not available." >&2
  exit 1
fi

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set. Start this script from a Linux desktop session with X11/XWayland." >&2
  exit 1
fi

if [[ ! -d /tmp/.X11-unix ]]; then
  echo "/tmp/.X11-unix was not found. X11 forwarding is not available on this host." >&2
  exit 1
fi

mkdir -p workspace

if [[ -n "${XAUTHORITY:-}" && -f "$XAUTHORITY" ]]; then
  export XAUTHORITY_PATH="$XAUTHORITY"
elif [[ -f "${HOME}/.Xauthority" ]]; then
  export XAUTHORITY_PATH="${HOME}/.Xauthority"
else
  export XAUTHORITY_PATH=/dev/null
fi

if command -v xhost >/dev/null 2>&1; then
  XHOST_LOCALUSER_GRANTED=0
  XHOST_DOCKER_GRANTED=0

  if xhost +SI:localuser:"$(id -un)" >/dev/null 2>&1; then
    XHOST_LOCALUSER_GRANTED=1
  fi

  if xhost +local:docker >/dev/null 2>&1; then
    XHOST_DOCKER_GRANTED=1
  fi

  if [[ "$XHOST_LOCALUSER_GRANTED" != "1" && "$XHOST_DOCKER_GRANTED" != "1" ]]; then
    echo "xhost could not grant X server access." >&2
    exit 1
  fi

  XHOST_GRANTED=1
else
  echo "xhost command not found. Continuing without changing X server access control." >&2
  XHOST_GRANTED=0
fi

cleanup() {
  if [[ "${XHOST_GRANTED:-0}" == "1" ]] && command -v xhost >/dev/null 2>&1; then
    if [[ "${XHOST_LOCALUSER_GRANTED:-0}" == "1" ]]; then
      xhost -SI:localuser:"$(id -un)" >/dev/null || true
    fi
    if [[ "${XHOST_DOCKER_GRANTED:-0}" == "1" ]]; then
      xhost -local:docker >/dev/null || true
    fi
  fi
}
trap cleanup EXIT

env UID="$(id -u)" GID="$(id -g)" docker compose run --rm gcoordinator
