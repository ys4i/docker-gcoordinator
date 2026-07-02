#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_URL="https://github.com/ys4i/docker-gcoordinator.git"
INSTALL_DIR="${GCOORDINATOR_INSTALL_DIR:-$HOME/Projects/docker-gcoordinator}"
STATE_FILE="$HOME/Library/Application Support/docker-gcoordinator/built-revision"
ACTION=""

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer must be run on macOS." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Git is required. Run 'xcode-select --install' and retry." >&2
  exit 1
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
  origin_url="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
  case "$origin_url" in
    https://github.com/ys4i/docker-gcoordinator.git | \
      https://github.com/ys4i/docker-gcoordinator | \
      git@github.com:ys4i/docker-gcoordinator.git)
      ;;
    *)
      echo "$INSTALL_DIR exists but is not the expected repository." >&2
      echo "Current origin: ${origin_url:-not configured}" >&2
      exit 1
      ;;
  esac

  echo "Updating the existing installation..."
  previous_revision="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
  git -C "$INSTALL_DIR" pull --ff-only
  current_revision="$(git -C "$INSTALL_DIR" rev-parse HEAD)"

  if [[ "$previous_revision" != "$current_revision" ]]; then
    ACTION="setup"
  fi
elif [[ -e "$INSTALL_DIR" ]]; then
  echo "$INSTALL_DIR already exists but is not a Git repository." >&2
  exit 1
else
  echo "Installing docker-gcoordinator into $INSTALL_DIR..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPOSITORY_URL" "$INSTALL_DIR"
  current_revision="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
  ACTION="setup"
fi

if [[ "$#" -gt 0 ]]; then
  ACTION="setup"
elif [[ ! -f "$STATE_FILE" ]] ||
  [[ "$(<"$STATE_FILE")" != "$current_revision" ]]; then
  ACTION="setup"
elif [[ ! -d /Applications/Docker.app ]]; then
  ACTION="setup"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  if ! docker image inspect docker-gcoordinator:latest >/dev/null 2>&1; then
    ACTION="setup"
  fi
fi

if [[ "$ACTION" == "setup" ]]; then
  echo "Setup is required. Running setup-macos.sh..."
  exec bash "$INSTALL_DIR/scripts/setup-macos.sh" "$@"
fi

echo "Installation is current. Running run-macos.sh..."
exec bash "$INSTALL_DIR/scripts/run-macos.sh"
