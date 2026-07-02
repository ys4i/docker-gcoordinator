#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [[ "$(id -u)" -eq 0 ]]; then
  CURRENT_USER="${1:-}"
  if [[ ! "$CURRENT_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
    ! id "$CURRENT_USER" >/dev/null 2>&1; then
    echo "When run as root, specify an existing regular WSL user." >&2
    exit 1
  fi
  SUDO=()
else
  CURRENT_USER="$(id -un)"
  SUDO=(sudo)
fi

start_docker() {
  if docker info >/dev/null 2>&1; then
    return
  fi

  if command -v systemctl >/dev/null 2>&1 && [[ "$(ps -p 1 -o comm=)" == "systemd" ]]; then
    "${SUDO[@]}" systemctl enable --now docker
  else
    "${SUDO[@]}" service docker start
  fi
}

if ! dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q 'install ok installed' ||
  ! command -v docker >/dev/null 2>&1 ||
  ! docker compose version >/dev/null 2>&1; then
  echo "Installing Docker Engine and the Compose plugin in WSL Ubuntu..."
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y ca-certificates curl

  CONFLICTING_PACKAGES=()
  for package in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
      CONFLICTING_PACKAGES+=("$package")
    fi
  done
  if [[ "${#CONFLICTING_PACKAGES[@]}" -gt 0 ]]; then
    "${SUDO[@]}" apt-get remove -y "${CONFLICTING_PACKAGES[@]}"
  fi

  "${SUDO[@]}" install -m 0755 -d /etc/apt/keyrings
  "${SUDO[@]}" curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  "${SUDO[@]}" chmod a+r /etc/apt/keyrings/docker.asc

  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "This setup supports Ubuntu only. Detected distribution: ${ID:-unknown}" >&2
    exit 1
  fi

  ARCH="$(dpkg --print-architecture)"
  CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  if [[ -z "$CODENAME" ]]; then
    echo "Could not determine the Ubuntu codename." >&2
    exit 1
  fi

  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $CODENAME stable" |
    "${SUDO[@]}" tee /etc/apt/sources.list.d/docker.list >/dev/null

  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

if ! id -nG "$CURRENT_USER" | tr ' ' '\n' | grep -qx docker; then
  echo "Adding $CURRENT_USER to the docker group..."
  "${SUDO[@]}" usermod -aG docker "$CURRENT_USER"
fi

# The Docker group already grants root-equivalent Docker access. This narrowly
# allows the same user to restart only the Docker service after WSL shuts down.
printf '%s ALL=(root) NOPASSWD: /usr/sbin/service docker start\n' "$CURRENT_USER" |
  "${SUDO[@]}" tee /etc/sudoers.d/docker-wsl-start >/dev/null
"${SUDO[@]}" chmod 0440 /etc/sudoers.d/docker-wsl-start

start_docker

if ! docker info >/dev/null 2>&1; then
  echo "Verifying Docker Engine with elevated privileges..."
  if ! "${SUDO[@]}" docker info >/dev/null; then
    echo "Docker Engine was installed but is not ready." >&2
    exit 1
  fi
fi

if ! docker compose version >/dev/null 2>&1; then
  if ! "${SUDO[@]}" docker compose version >/dev/null; then
    echo "Docker Compose plugin is not available." >&2
    exit 1
  fi
fi

echo "Docker Engine and Docker Compose are ready in WSL."
