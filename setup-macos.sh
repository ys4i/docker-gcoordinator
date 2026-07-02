#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NO_BUILD=0
NO_LAUNCH=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --no-build)
      NO_BUILD=1
      ;;
    --no-launch)
      NO_LAUNCH=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--no-build] [--no-launch]" >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS." >&2
  exit 1
fi

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run this script as a regular macOS user, not with sudo." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to install Homebrew." >&2
    exit 1
  fi

  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "Homebrew installation completed, but the brew command was not found." >&2
    exit 1
  fi
fi

if [[ ! -d /Applications/Docker.app ]]; then
  echo "Installing Docker Desktop..."
  brew install --cask docker-desktop
else
  echo "Docker Desktop is already installed."
fi

if [[ ! -d /Applications/Utilities/XQuartz.app ]]; then
  echo "Installing XQuartz..."
  brew install --cask xquartz
else
  echo "XQuartz is already installed."
fi

echo "Enabling XQuartz network client connections..."
defaults write org.xquartz.X11 nolisten_tcp -bool false

# Apply the preference to a new XQuartz process. The normal quit request is
# attempted first so existing X11 clients can shut down cleanly.
if pgrep -x Xquartz >/dev/null 2>&1; then
  osascript -e 'tell application "XQuartz" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -x Xquartz >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

if pgrep -x Xquartz >/dev/null 2>&1; then
  echo "XQuartz did not exit normally. Stopping it..."
  pkill -TERM -x Xquartz >/dev/null 2>&1 || true
  for _ in {1..10}; do
    if ! pgrep -x Xquartz >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

if pgrep -x Xquartz >/dev/null 2>&1; then
  echo "Forcing the old XQuartz process to stop..."
  pkill -KILL -x Xquartz >/dev/null 2>&1 || true
  sleep 1
fi

if pgrep -x Xquartz >/dev/null 2>&1; then
  echo "Could not stop the old XQuartz process." >&2
  exit 1
fi

open -a XQuartz

echo "Starting Docker Desktop..."
open -a Docker

if ! command -v docker >/dev/null 2>&1 &&
  [[ -x /Applications/Docker.app/Contents/Resources/bin/docker ]]; then
  export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
fi

echo "Waiting for Docker Desktop to become ready..."
DOCKER_READY=0
for attempt in {1..600}; do
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    DOCKER_READY=1
    break
  fi
  if (( attempt % 30 == 0 )); then
    echo "Still waiting for Docker Desktop. Complete any first-run dialog if one is open..."
  fi
  sleep 1
done

if [[ "$DOCKER_READY" != "1" ]]; then
  echo "Docker Desktop did not become ready within 10 minutes." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is not available. Update Docker Desktop." >&2
  exit 1
fi

mkdir -p workspace log

if [[ "$NO_BUILD" != "1" ]]; then
  echo "Building the g-coordinator Docker image..."
  docker compose -f docker-compose.yml -f docker-compose.macos.yml build
fi

echo "macOS setup completed."

if [[ "$NO_LAUNCH" == "1" ]]; then
  echo "Run: ./run-macos.sh"
  exit 0
fi

echo "Launching g-coordinator..."
exec ./run-macos.sh
