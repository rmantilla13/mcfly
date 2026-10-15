#!/usr/bin/env bash
# Runs McFly on a virtual 1920x1200 screen (the 10.1" panel) and serves it to
# a web browser through noVNC, so the Pi can be used before the panel arrives.
# Installed as /usr/local/bin/mcfly-preview and started by the mcfly-preview
# service; turn it on and off with display/deploy/preview.sh.
#
# Everything listens on localhost (reach it through an SSH tunnel), unless
# MCFLY_PREVIEW_LAN=1, which opens the browser page to the local network
# behind the VNC password in /etc/mcfly/preview.passwd.
set -euo pipefail

screen_num="${MCFLY_PREVIEW_SCREEN:-5}"
vnc_port="${MCFLY_PREVIEW_VNC_PORT:-5900}"
web_port="${MCFLY_PREVIEW_WEB_PORT:-6080}"
app="${MCFLY_DISPLAY_BIN:-/usr/local/bin/mcfly-display}"
env_file="${MCFLY_DISPLAY_ENV:-/etc/mcfly/display.env}"
passwd_file="${MCFLY_PREVIEW_PASSWD:-/etc/mcfly/preview.passwd}"
novnc_dir="${MCFLY_NOVNC_DIR:-/usr/share/novnc}"

# The device's own settings (scale, backend, idle time), drawn into X instead
# of straight to the panel.
if [ -f "$env_file" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
fi
unset QT_QPA_EGLFS_INTEGRATION QT_QPA_EGLFS_KMS_CONFIG QT_QPA_EGLFS_HIDECURSOR
export QT_QPA_PLATFORM=xcb DISPLAY=":$screen_num"

pids=()
# shellcheck disable=SC2317  # called by the trap
cleanup() { kill "${pids[@]}" 2>/dev/null || true; }
trap cleanup EXIT

# A virtual screen the size of the panel. Qt Quick renders into it with Mesa's
# software OpenGL, so blur and rounded-photo effects look like the real thing.
rm -f "/tmp/.X$screen_num-lock"
Xvfb ":$screen_num" -screen 0 1920x1200x24 -nolisten tcp &
pids+=($!)
for _ in $(seq 100); do
    [ -S "/tmp/.X11-unix/X$screen_num" ] && break
    sleep 0.1
done
[ -S "/tmp/.X11-unix/X$screen_num" ] || { echo "Xvfb didn't start" >&2; exit 1; }

"$app" "$@" &
pids+=($!)

# VNC only ever listens on localhost; the browser page proxies to it.
auth=(-nopw)
if [ "${MCFLY_PREVIEW_LAN:-0}" = 1 ]; then
    [ -r "$passwd_file" ] || { echo "MCFLY_PREVIEW_LAN=1 needs a password in $passwd_file (run preview.sh on --lan)" >&2; exit 1; }
    auth=(-rfbauth "$passwd_file")
fi
x11vnc -display ":$screen_num" -localhost -rfbport "$vnc_port" -forever -shared -quiet "${auth[@]}" &
pids+=($!)

web_host=127.0.0.1
[ "${MCFLY_PREVIEW_LAN:-0}" = 1 ] && web_host=0.0.0.0
websockify --web "$novnc_dir" "$web_host:$web_port" "127.0.0.1:$vnc_port" &
pids+=($!)

# If any piece stops, stop the rest; the service starts them all again.
wait -n
exit 1
