#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NO_BUILD=0
NO_LAUNCH=0
GROUP_READY=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --no-build)
      NO_BUILD=1
      ;;
    --no-launch)
      NO_LAUNCH=1
      ;;
    --group-ready)
      GROUP_READY=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--no-build] [--no-launch]" >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Linux" ]] ||
  grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  echo "This setup script must be run on a native Linux host." >&2
  exit 1
fi

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run this script as a regular Linux user, not as root." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1 ||
  ! docker compose version >/dev/null 2>&1; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Docker Engine and Compose are missing." >&2
    echo "Automatic installation supports Ubuntu and Debian; install Docker manually on this distribution." >&2
    exit 1
  fi

  echo "Installing Docker Engine and Docker Compose..."
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl

  conflicting_packages=()
  for package in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
      grep -q 'install ok installed'; then
      conflicting_packages+=("$package")
    fi
  done
  if (( ${#conflicting_packages[@]} > 0 )); then
    sudo apt-get remove -y "${conflicting_packages[@]}"
  fi

  sudo install -m 0755 -d /etc/apt/keyrings

  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu | debian)
      ;;
    *)
      echo "Automatic Docker installation supports Ubuntu and Debian only." >&2
      exit 1
      ;;
  esac

  sudo curl -fsSL "https://download.docker.com/linux/$ID/gpg" \
    -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  architecture="$(dpkg --print-architecture)"
  codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  if [[ -z "$codename" ]]; then
    echo "Could not determine the distribution codename." >&2
    exit 1
  fi

  printf 'Types: deb\nURIs: https://download.docker.com/linux/%s\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
    "$ID" "$codename" "$architecture" |
    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
fi

if ! id -nG | tr ' ' '\n' | grep -qx docker; then
  echo "Adding $(id -un) to the docker group..."
  sudo usermod -aG docker "$(id -un)"
  if [[ "$GROUP_READY" != "1" ]]; then
    args=(--group-ready)
    [[ "$NO_BUILD" == "1" ]] && args+=(--no-build)
    [[ "$NO_LAUNCH" == "1" ]] && args+=(--no-launch)
    printf -v command 'bash %q' "$SCRIPT_DIR/setup-linux.sh"
    printf -v quoted_args ' %q' "${args[@]}"
    exec sg docker -c "$command$quoted_args"
  fi
fi

if ! docker info >/dev/null 2>&1; then
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now docker
  else
    sudo service docker start
  fi
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker Engine is not ready." >&2
  exit 1
fi

mkdir -p workspace log

if [[ "$NO_BUILD" != "1" ]]; then
  echo "Building the g-coordinator Docker image..."
  docker compose -f docker-compose.yml -f docker-compose.linux.yml build

  if revision="$(git rev-parse HEAD 2>/dev/null)"; then
    state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/docker-gcoordinator"
    mkdir -p "$state_dir"
    printf '%s\n' "$revision" >"$state_dir/linux-built-revision"
  fi
fi

echo "Linux setup completed."

if [[ "$NO_LAUNCH" == "1" ]]; then
  echo "Run: ./run-linux.sh"
  exit 0
fi

echo "Launching g-coordinator..."
exec bash ./run-linux.sh
