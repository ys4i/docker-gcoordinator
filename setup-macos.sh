#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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
  echo "XQuartz did not exit. Close it and run this script again." >&2
  exit 1
fi

open -a XQuartz

echo "Starting Docker Desktop..."
open -a Docker

echo "Waiting for Docker Desktop to become ready..."
for _ in {1..120}; do
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    mkdir -p workspace
    echo "macOS setup completed."
    echo "Run: ./run-macos.sh"
    exit 0
  fi
  sleep 1
done

echo "Docker Desktop was installed and started, but is not ready yet." >&2
echo "Complete any first-run dialogs in Docker Desktop, then run ./run-macos.sh." >&2
exit 1
