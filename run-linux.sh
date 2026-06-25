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

COMPOSE_FILES=(-f docker-compose.yml)
GPU_COMPOSE_FILE=""

cleanup_gpu_compose_file() {
  if [[ -n "${GPU_COMPOSE_FILE:-}" && -f "$GPU_COMPOSE_FILE" ]]; then
    rm -f "$GPU_COMPOSE_FILE"
  fi
}
trap cleanup_gpu_compose_file EXIT

if [[ -d /dev/dri ]]; then
  GPU_COMPOSE_FILE="$(mktemp /tmp/docker-gcoordinator-gpu.XXXXXX.yml)"
  {
    printf '%s\n' 'services:'
    printf '%s\n' '  gcoordinator:'
    printf '%s\n' '    devices:'
    printf '%s\n' '      - /dev/dri:/dev/dri'

    mapfile -t DRI_GROUP_IDS < <(
      find /dev/dri -mindepth 1 -maxdepth 1 -printf '%G\n' 2>/dev/null | sort -n | uniq
    )

    if (( ${#DRI_GROUP_IDS[@]} > 0 )); then
      printf '%s\n' '    group_add:'
      for group_id in "${DRI_GROUP_IDS[@]}"; do
        printf '      - "%s"\n' "$group_id"
      done
    fi
  } > "$GPU_COMPOSE_FILE"

  COMPOSE_FILES+=(-f "$GPU_COMPOSE_FILE")
  echo "GPU/DRI enabled: /dev/dri will be passed to the container."
else
  echo "GPU/DRI disabled: /dev/dri was not found. Falling back to X11 GLX without device passthrough." >&2
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
  cleanup_gpu_compose_file

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

env UID="$(id -u)" GID="$(id -g)" docker compose "${COMPOSE_FILES[@]}" run --rm gcoordinator
