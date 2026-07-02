#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found. Run setup-windows.ps1 first." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Starting Docker Engine..."
  sudo -n /usr/sbin/service docker start
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker Engine is not running." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose is not available." >&2
  exit 1
fi

WINDOWS_HOST_CANDIDATES=()
if [[ -n "${GCOORDINATOR_WINDOWS_HOST:-}" ]]; then
  WINDOWS_HOST_CANDIDATES+=("$GCOORDINATOR_WINDOWS_HOST")
fi

DEFAULT_GATEWAY="$(ip route show default 2>/dev/null | awk '{ print $3; exit }')"
if [[ -n "$DEFAULT_GATEWAY" ]]; then
  WINDOWS_HOST_CANDIDATES+=("$DEFAULT_GATEWAY")
fi

DNS_HOST="$(awk '/^nameserver / { print $2; exit }' /etc/resolv.conf 2>/dev/null || true)"
if [[ -n "$DNS_HOST" ]]; then
  WINDOWS_HOST_CANDIDATES+=("$DNS_HOST")
fi
WINDOWS_HOST_CANDIDATES+=("127.0.0.1")

WINDOWS_HOST=""
for candidate in "${WINDOWS_HOST_CANDIDATES[@]}"; do
  if [[ ! "$candidate" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
    continue
  fi
  if timeout 2 bash -c 'exec 3<>"/dev/tcp/$1/6000"' _ "$candidate" 2>/dev/null; then
    WINDOWS_HOST="$candidate"
    break
  fi
done

if [[ -z "$WINDOWS_HOST" ]]; then
  echo "Could not connect from WSL to VcXsrv on TCP port 6000." >&2
  echo "Check that VcXsrv is running and allowed through Windows Defender Firewall." >&2
  exit 1
fi

export DISPLAY="${WINDOWS_HOST}:0.0"
echo "VcXsrv connection verified: DISPLAY=$DISPLAY"

env UID="$(id -u)" GID="$(id -g)" \
  docker compose -f docker-compose.yml -f docker-compose.windows.yml run --rm gcoordinator
