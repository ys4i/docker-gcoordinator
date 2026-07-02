#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
WSL_USER="${2:-}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This helper must be run as root by setup-windows.ps1." >&2
  exit 1
fi

if [[ ! "$WSL_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Invalid WSL user name: $WSL_USER" >&2
  exit 1
fi

case "$ACTION" in
  prepare)
    if ! id "$WSL_USER" >/dev/null 2>&1; then
      echo "Creating WSL user '$WSL_USER'..." >&2
      useradd --create-home --shell /bin/bash "$WSL_USER"
    fi

    WSL_CONF_TMP="$(mktemp)"
    trap 'rm -f "${WSL_CONF_TMP:-}"' EXIT
    WSL_CONF_SOURCE="/etc/wsl.conf"
    if [[ ! -f "$WSL_CONF_SOURCE" ]]; then
      WSL_CONF_SOURCE="/dev/null"
    fi
    awk -v user="$WSL_USER" '
      BEGIN { in_user = 0; found_user = 0; wrote_default = 0 }
      /^\[user\][[:space:]]*$/ {
        if (in_user && !wrote_default) {
          print "default=" user
          wrote_default = 1
        }
        in_user = 1
        found_user = 1
        print
        next
      }
      /^\[/ {
        if (in_user && !wrote_default) {
          print "default=" user
          wrote_default = 1
        }
        in_user = 0
      }
      in_user && /^[[:space:]]*default[[:space:]]*=/ {
        if (!wrote_default) {
          print "default=" user
          wrote_default = 1
        }
        next
      }
      { print }
      END {
        if (in_user && !wrote_default) {
          print "default=" user
        } else if (!found_user) {
          print ""
          print "[user]"
          print "default=" user
        }
      }
    ' "$WSL_CONF_SOURCE" >"$WSL_CONF_TMP"
    install -m 0644 "$WSL_CONF_TMP" /etc/wsl.conf
    rm -f "$WSL_CONF_TMP"
    trap - EXIT

    ;;
  *)
    echo "Usage: $0 prepare USER" >&2
    exit 2
    ;;
esac
