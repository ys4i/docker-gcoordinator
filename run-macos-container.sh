#!/usr/bin/env sh
set -eu

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

Xvfb :99 -screen 0 1440x900x24 +extension GLX +render -noreset &
xvfb_pid=$!

cleanup() {
    if [ -n "${x11vnc_pid:-}" ]; then
        kill "$x11vnc_pid" >/dev/null 2>&1 || true
    fi
    kill "$xvfb_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

attempt=0
while [ ! -S /tmp/.X11-unix/X99 ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 100 ]; then
        echo "Xvfb did not become ready." >&2
        exit 1
    fi
    sleep 0.1
done

x11vnc -storepasswd "$VNC_PASSWORD" /tmp/vnc.pass >/dev/null 2>&1
chmod 600 /tmp/vnc.pass

x11vnc -display :99 -forever -shared -rfbauth /tmp/vnc.pass -rfbport 5900 \
    -listen 0.0.0.0 >/tmp/x11vnc.log 2>&1 &
x11vnc_pid=$!

python3 main.py
