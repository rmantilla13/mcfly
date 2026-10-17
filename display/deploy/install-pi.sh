#!/usr/bin/env bash
# Sets up a Raspberry Pi 5 (Raspberry Pi OS, 64-bit) as an McFly display:
# installs dependencies, builds and installs the app, and starts it now and
# on every boot. The service takes the console, so a reboot shows McFly
# instead of the login prompt.
#
#   git clone https://github.com/rmantilla13/mcfly && cd mcfly
#   ./display/deploy/install-pi.sh                # display only
#   ./display/deploy/install-pi.sh --with-voice   # plus the voice service (wake word,
#                                                 # spoken answers); or MCFLY_VOICE=1
#   ./display/deploy/install-pi.sh --with-voice --skip-models
#                                                 # fetch the voice models later;
#                                                 # or MCFLY_VOICE_SKIP_MODELS=1
#
# Safe to re-run, also after an interrupted run: it rebuilds, reinstalls and
# restarts the app (and updates the voice service if it's installed), and
# keeps an existing /etc/mcfly/display.env. A file at /etc/mcfly/boot.mp4
# replaces the built-in boot video; the next reboot plays it.
set -euo pipefail

if [ "$(uname -s)" != Linux ]; then
    echo "This runs on the Raspberry Pi. Log in to it first (ssh <user>@mcfly.local)." >&2
    exit 1
fi

repo="$(cd "$(dirname "$0")/../.." && pwd)"
user="$(id -un)"
uid="$(id -u)"
with_voice="${MCFLY_VOICE:-0}"
skip_models="${MCFLY_VOICE_SKIP_MODELS:-0}"
for arg in "$@"; do
    case "$arg" in
        --with-voice) with_voice=1 ;;
        --skip-models) skip_models=1 ;;
        *) echo "Unknown option: $arg (try --with-voice or --skip-models)" >&2; exit 2 ;;
    esac
done
if [ "$uid" -eq 0 ]; then
    echo "Run this as your normal user; it uses sudo where needed." >&2
    exit 1
fi

step() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

step "Installing packages"
# First finish any package install that was cut off (say, a dropped SSH
# connection); apt refuses to run until that's done.
sudo dpkg --configure -a
# Sound: Qt plays video sound through PulseAudio, which Lite doesn't run;
# PipeWire provides it. libasound2-plugins lets ALSA programs use it too.
# Boot video: the ffmpeg package includes ffplay, which draws on the KMS/DRM
# screen before the app starts. ffmpeg itself is the framebuffer fallback.
# qt6-base-private-dev: lets the app switch the HDMI panel off when it sleeps.
# qt6-image-formats-plugins: WebP pictures, which many News stories serve;
# without it they fall back to a tinted tile.
# Games (display/games/README.md): particles for Same Game and Maroon,
# LocalStorage and SQLite for the scores, QtMultimedia for Maroon's sounds
# (on Trixie its FFmpeg backend comes with libqt6multimedia6).
# A Pi on weak Wi-Fi drops downloads: retry each one, and MCFLY_FORCE_IPV4=1
# skips IPv6 where the network advertises it but doesn't route it.
apt_opts=(-o Acquire::Retries=5 -o Acquire::http::Timeout=30)
[ "${MCFLY_FORCE_IPV4:-}" = 1 ] && apt_opts+=(-o Acquire::ForceIPv4=true)
sudo apt-get "${apt_opts[@]}" update
sudo apt-get "${apt_opts[@]}" install -y \
    build-essential cmake git \
    qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-websockets-dev qt6-qpa-plugins \
    qt6-shadertools-dev libqt6websockets6 qt6-image-formats-plugins \
    qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
    qml6-module-qtquick-window qml6-module-qtquick-templates qml6-module-qtqml-workerscript \
    qml6-module-qtquick-shapes \
    qml6-module-qtquick-virtualkeyboard qt6-virtualkeyboard-plugin \
    qml6-module-qtquick-particles qml6-module-qtquick-localstorage libqt6sql6-sqlite \
    qml6-module-qtmultimedia \
    pipewire pipewire-pulse wireplumber libasound2-plugins alsa-utils \
    fonts-inter fonts-noto-color-emoji \
    ffmpeg curl

step "Building mcfly-display"
cmake -S "$repo/display" -B "$repo/build/display" -DCMAKE_BUILD_TYPE=Release -DMCFLY_BUILD_TESTS=OFF
cmake --build "$repo/build/display" -j"$(nproc)"
sudo cmake --install "$repo/build/display" --prefix /usr/local

step "Granting display, GPU, touch, sound and console access to $user"
# The app runs without a desktop login, so these groups are what let it open
# the screen, the GPU, the touch panel, the sound card and the console.
for group in video render input audio tty; do
    getent group "$group" >/dev/null && sudo usermod -aG "$group" "$user"
done

step "Letting this display change Wi-Fi and reboot"
# The app has no password prompt, so a root-owned helper is the only thing
# sudo will run without asking. It changes Wi-Fi and reboots, and nothing else.
sudo install -D -m 755 "$repo/display/deploy/mcfly-system" /usr/local/libexec/mcfly-system
sudo tee /etc/sudoers.d/mcfly-system >/dev/null <<EOF
# McFly display: Wi-Fi and reboot only.
$user ALL=(root) NOPASSWD: /usr/local/libexec/mcfly-system
EOF
sudo chmod 440 /etc/sudoers.d/mcfly-system
sudo visudo -cf /etc/sudoers.d/mcfly-system

# kms-pick-begin
# Print the DRM card and Qt's eglfs output name for the panel.
# The kernel calls the Pi's HDMI0 port (next to USB-C) HDMI-A-1. Qt's
# eglfs_kms calls that same connector HDMI1, and HDMI-A-2 is HDMI2.
# A connected connector wins. HDMI-A-1 wins a tie, and it is the fallback
# when the panel is still off, so the app opens that port once it comes on.
mcfly_pick_hdmi() {
    local sysroot="${1:-/sys/class/drm}"
    local connector base dev name qt status
    local preferred_card="" preferred_output="" fallback_card="" fallback_output=""
    local card="/dev/dri/card1" output="HDMI1"
    for connector in "$sysroot"/card*-HDMI-A-*; do
        [ -e "$connector" ] || continue
        base=$(basename "$connector")
        dev="/dev/dri/${base%%-*}"
        name="${base#*-}"
        case "$name" in
            HDMI-A-*) qt="HDMI${name#HDMI-A-}" ;;
            *) qt="HDMI1" ;;
        esac
        status=""
        if [ -f "$connector/status" ]; then
            status=$(cat "$connector/status" 2>/dev/null || true)
        fi
        if [ "$name" = "HDMI-A-1" ]; then
            fallback_card=$dev
            fallback_output=$qt
        elif [ -z "$fallback_card" ]; then
            fallback_card=$dev
            fallback_output=$qt
        fi
        if [ "$status" = "connected" ]; then
            if [ -z "$preferred_card" ] || [ "$name" = "HDMI-A-1" ]; then
                preferred_card=$dev
                preferred_output=$qt
            fi
        fi
    done
    if [ -n "$preferred_card" ]; then
        card=$preferred_card
        output=$preferred_output
    elif [ -n "$fallback_card" ]; then
        card=$fallback_card
        output=$fallback_output
    fi
    printf '%s\n%s\n' "$card" "$output"
}
# kms-pick-end

step "Configuring the display"
# On the Pi 5 the GPU (render only) and the display controller are separate DRM
# devices, and their card numbers can swap between boots. Qt has to open the
# one that drives HDMI, so use its stable /dev/dri/by-path name.
mapfile -t picked < <(mcfly_pick_hdmi /sys/class/drm)
card="${picked[0]}"
output="${picked[1]}"
for link in /dev/dri/by-path/*-card; do
    if [ -e "$link" ] && [ "$(readlink -f "$link")" = "$(readlink -f "$card")" ]; then
        card="$link"
        break
    fi
done
echo "Using $card ($output) for HDMI output"

# 1920x1200 is the panel's resolution; a screen that doesn't offer it gets
# its own preferred mode instead.
sudo mkdir -p /etc/mcfly
sudo tee /etc/mcfly/kms.json >/dev/null <<JSON
{
  "device": "$card",
  "hwcursor": false,
  "outputs": [ { "name": "$output", "mode": "1920x1200" } ]
}
JSON

if [ ! -f /etc/mcfly/display.env ]; then
    sudo tee /etc/mcfly/display.env >/dev/null <<'ENV'
# McFly display settings. Restart after editing: sudo systemctl restart mcfly-display
QT_QPA_PLATFORM=eglfs
QT_QPA_EGLFS_INTEGRATION=eglfs_kms
QT_QPA_EGLFS_KMS_CONFIG=/etc/mcfly/kms.json
QT_QPA_EGLFS_HIDECURSOR=1
QT_QPA_EGLFS_ALWAYS_SET_MODE=1
QT_IM_MODULE=qtvirtualkeyboard
# Date and time formats (Raspberry Pi OS defaults to en_GB). The on-screen
# keyboard is US English either way.
LANG=en_US.UTF-8
# 1.5 suits the 10.1" 1920x1200 panel; use 1.0 for ~21" 1080p screens.
QT_SCALE_FACTOR=1.5
# Seconds without a touch before the screen saver starts.
MCFLY_IDLE_SECONDS=120

# Uncomment to connect to your Supabase project (otherwise it runs with demo data):
#MCFLY_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
#MCFLY_SUPABASE_ANON_KEY=YOUR-ANON-KEY
# The on-device voice service (install with install-pi.sh --with-voice).
#MCFLY_VOICE_URL=ws://127.0.0.1:8765
# Seconds the boot video waits for Wi-Fi, so McFly opens connected (0-60).
#MCFLY_BOOT_NETWORK_WAIT=30
ENV
else
    echo "Keeping existing /etc/mcfly/display.env"
fi
# Lines are appended below. A hand-edited file may not end in a newline, and
# the new line would then run into its last value.
end_with_newline() {
    if [ -s "$1" ] && [ -n "$(sudo tail -c 1 "$1")" ]; then
        echo | sudo tee -a "$1" >/dev/null
    fi
}
# A file left by an older install can omit the KMS lines. Qt then never opens
# HDMI and the service stays up on a text console. Fill those keys in place
# and leave scale, language and Supabase settings alone.
ensure_display_env() {
    local key="$1" value="$2" file=/etc/mcfly/display.env
    if sudo grep -qE "^${key}=" "$file"; then
        sudo sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        end_with_newline "$file"
        printf '%s=%s\n' "$key" "$value" | sudo tee -a "$file" >/dev/null
    fi
}
ensure_display_env QT_QPA_PLATFORM eglfs
ensure_display_env QT_QPA_EGLFS_INTEGRATION eglfs_kms
ensure_display_env QT_QPA_EGLFS_KMS_CONFIG /etc/mcfly/kms.json
ensure_display_env QT_QPA_EGLFS_HIDECURSOR 1
ensure_display_env QT_QPA_EGLFS_ALWAYS_SET_MODE 1
# No backend yet (a fresh install, or one still on demo data): connect to the
# repo's default, mcfly.bot's project (display/deploy/backend.env), so the
# first boot shows the pairing code. A backend set by hand is kept.
if ! sudo grep -qE '^MCFLY_SUPABASE_URL=' /etc/mcfly/display.env && [ -f "$repo/display/deploy/backend.env" ]; then
    echo "Connecting to the default backend (display/deploy/backend.env)"
    ensure_display_env MCFLY_SUPABASE_URL "$(grep -E '^MCFLY_SUPABASE_URL=' "$repo/display/deploy/backend.env" | cut -d= -f2-)"
    ensure_display_env MCFLY_SUPABASE_ANON_KEY "$(grep -E '^MCFLY_SUPABASE_ANON_KEY=' "$repo/display/deploy/backend.env" | cut -d= -f2-)"
fi

step "Configuring the console"
# Hide the rainbow splash and the kernel log, and keep the console from
# blanking or showing a cursor behind the app. The panel then stays dark
# until the boot video (or McFly) draws, instead of scrolling boot text.
# SSH is unchanged. Takes effect on reboot.
"$repo/display/deploy/quiet-boot.sh"

# cloud-init prints "Completed socket interaction for boot stage final" on
# the HDMI console after quiet boot. The kernel command line does not stop
# it: those units use StandardOutput=journal+console. Send that to the
# journal, and keep cloud-init's own log off the console. A reboot applies it.
sudo mkdir -p /etc/cloud/cloud.cfg.d
sudo tee /etc/cloud/cloud.cfg.d/99-mcfly-quiet.cfg >/dev/null <<'EOF'
# Written by McFly install-pi.sh. Boot-stage text stays in the log.
output: {all: ">> /var/log/cloud-init-output.log"}
EOF
for unit in cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service; do
    if [ ! -f "/lib/systemd/system/$unit" ] && [ ! -f "/usr/lib/systemd/system/$unit" ]; then
        continue
    fi
    sudo mkdir -p "/etc/systemd/system/${unit}.d"
    sudo tee "/etc/systemd/system/${unit}.d/mcfly-quiet.conf" >/dev/null <<'EOF'
# Written by McFly install-pi.sh. Do not paint the HDMI console.
[Service]
StandardOutput=journal
StandardError=journal
EOF
done

step "Setting up sound (the panel's speakers, over HDMI)"
# PipeWire runs as $user's own service. Lingering starts it at boot, without
# anyone logging in. (Without logind, as in a container, write the flag file
# that loginctl would.)
if ! sudo loginctl enable-linger "$user" 2>/dev/null; then
    sudo mkdir -p /var/lib/systemd/linger
    sudo touch "/var/lib/systemd/linger/$user"
fi
# ALSA programs (the voice service's replies, speaker-test) play through
# PipeWire as well, so they mix with video sound instead of fighting over the
# HDMI port. While PipeWire isn't running they go straight to HDMI0.
if [ ! -f /etc/asound.conf ] || grep -q 'McFly' /etc/asound.conf; then
    sudo tee /etc/asound.conf >/dev/null <<ALSA
# Written by McFly install-pi.sh. Sound goes to PipeWire, or straight to the
# panel's speakers on HDMI0 (vc4hdmi0) when PipeWire isn't running. CARD is
# accepted (as in default:CARD=vc4hdmi0) and PipeWire picks the output.
pcm.!default {
    @args [ CARD ]
    @args.CARD { type string default "vc4hdmi0" }
    type pulse
    server "unix:/run/user/$uid/pulse/native"
    fallback "sysdefault:CARD=vc4hdmi0"
}
ctl.!default {
    @args [ CARD ]
    @args.CARD { type string default "vc4hdmi0" }
    type pulse
    server "unix:/run/user/$uid/pulse/native"
    fallback "hw:CARD=vc4hdmi0"
}
ALSA
else
    echo "Keeping your own /etc/asound.conf"
fi
# Full volume on this panel's HDMI speakers is mostly hiss. Start lower;
# the gear menu can turn them off or up. A volume set later is kept.
sudo mkdir -p /etc/wireplumber/wireplumber.conf.d
sudo tee /etc/wireplumber/wireplumber.conf.d/50-mcfly.conf >/dev/null <<'WP'
# Written by McFly install-pi.sh. 0.5 is loud enough for a video without
# the panel's amplifier sitting at full scale (that hiss). A volume set
# later with wpctl is kept instead.
wireplumber.settings = {
  device.routes.default-sink-volume = 0.5
}
WP
# Keep the speakers awake: the HDMI audio device opens as soon as PipeWire
# starts and stays open, carrying silence between sounds. Screens differ here.
# This one buzzes whenever HDMI audio stops (and until the first sound after a
# boot) and is quiet while it carries silence; others hiss while a stream is
# open (for those, set the timeout back to 1 and drop the other two lines).
# Holding a silent stream costs the Pi almost nothing.
sudo tee /etc/wireplumber/wireplumber.conf.d/51-mcfly-speakers.conf >/dev/null <<'WP'
# Written by McFly install-pi.sh. Open the speakers at startup and never close
# (suspend) or pause them when nothing plays, so the screen gets silence
# instead of buzzing.
monitor.alsa.rules = [
  {
    matches = [
      {
        node.name = "~alsa_output.*"
      }
    ]
    actions = {
      update-props = {
        session.suspend-timeout-seconds = 0
        node.pause-on-idle = false
        node.always-process = true
      }
    }
  }
]
WP
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    systemctl --user try-restart wireplumber.service pipewire.service pipewire-pulse.service || true
fi

if [ -d /etc/NetworkManager/conf.d ]; then
    step "Turning off Wi-Fi power saving"
    # It makes the Pi's Wi-Fi lag and drop out; the display is always plugged in.
    sudo tee /etc/NetworkManager/conf.d/mcfly-wifi-powersave.conf >/dev/null <<'NM'
# Written by McFly install-pi.sh: no Wi-Fi power saving (2 = disable).
[connection]
wifi.powersave = 2
NM
fi

step "Keeping SSH typing responsive"
# OpenSSH sets IP_TOS to low-delay (IPTOS_LOWDELAY). Many access points
# mishandle those packets, so keystrokes stutter over Wi-Fi even when the
# Pi is idle. cs0 leaves them unmarked. UseDNS skips a reverse lookup that
# only slows login. This file is McFly-owned and rewritten on every run.
# A reload applies it in the current session; a reboot is not required.
sudo mkdir -p /etc/ssh/sshd_config.d
sudo tee /etc/ssh/sshd_config.d/mcfly.conf >/dev/null <<'EOF'
# Written by McFly install-pi.sh.
IPQoS cs0 cs0
UseDNS no
EOF
sudo chmod 644 /etc/ssh/sshd_config.d/mcfly.conf
# Debian and Raspberry Pi OS name the unit ssh.service. Reload does not
# drop the session. If ssh is not running, the drop-in applies when it starts.
if systemctl is-active --quiet ssh; then
    sudo systemctl reload ssh
fi

step "Installing the boot video"
sudo install -d -m 755 /var/lib/mcfly
sudo install -D -m 755 "$repo/display/deploy/boot/mcfly-bootscreen" /usr/local/libexec/mcfly-bootscreen
sudo install -D -m 755 "$repo/display/deploy/boot/mcfly-stop-bootscreen" /usr/local/libexec/mcfly-stop-bootscreen
sudo install -D -m 644 "$repo/display/deploy/boot/boot.mp4" /usr/local/share/mcfly/boot.mp4
sudo install -D -m 644 "$repo/display/deploy/mcfly-bootscreen.service" /etc/systemd/system/mcfly-bootscreen.service

step "Installing the kiosk service"
sed -e "s/@USER@/$user/g" -e "s/@UID@/$uid/g" "$repo/display/deploy/mcfly-display.service" \
    | sudo tee /etc/systemd/system/mcfly-display.service >/dev/null
sudo install -m 644 "$repo/display/deploy/mcfly-display.pam" /etc/pam.d/mcfly-display
# Linger starts the user manager at boot. Start it now too, so /run/user/$uid
# exists (XDG_RUNTIME_DIR, PipeWire) before the kiosk is launched. Config
# above is already in place, so PipeWire picks it up.
if ! sudo systemctl start "user@${uid}.service"; then
    echo "User manager did not start yet; the kiosk retries once logind brings it up." >&2
fi
# The app needs the screen to itself, so boot to the console instead of a desktop.
if [ "$(systemctl get-default)" = "graphical.target" ]; then
    echo "Switching boot target from desktop to console (the app replaces the desktop)"
    sudo systemctl set-default multi-user.target
fi
# logind starts a login on tty1 when it thinks the console is idle. The kiosk
# holds that console; a prompt must not come back between restarts. Do not
# restart logind here: that drops the SSH session this script is running in.
# The file applies on the next boot. This boot stops getty below.
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/mcfly.conf >/dev/null <<'EOF'
# Written by McFly install-pi.sh.
# The kiosk owns tty1. Do not start a login prompt when the console looks idle.
[Login]
NAutoVTs=0
ReserveVT=0
EOF
sudo systemctl daemon-reload
# kiosk-boot-begin
if systemctl is-enabled --quiet mcfly-preview 2>/dev/null; then
    echo "Preview mode is on, so the kiosk stays off (./display/deploy/preview.sh off switches back)"
    sudo systemctl disable --now mcfly-display 2>/dev/null || true
    sudo systemctl disable --now mcfly-bootscreen 2>/dev/null || true
else
    # A previous install may have left this disabled or masked. enable writes
    # the multi-user.target.wants symlink, which is what a reboot starts.
    # --now starts it in this boot. restart then loads the binary this run
    # just installed (enable --now leaves an already-running process alone)
    # and also starts the unit if that first start did not stay up. Do not
    # skip this when the unit is inactive: that is a fresh install, and a
    # unit systemd dropped from the previous boot transaction.
    sudo systemctl unmask mcfly-display
    sudo systemctl unmask mcfly-bootscreen 2>/dev/null || true
    # Enabled for the next reboot only. Starting it now would fight the app
    # this restart is about to put on the screen. A failure here must not
    # skip enabling the kiosk.
    if ! sudo systemctl enable mcfly-bootscreen; then
        echo "Boot video was not enabled. The app still starts; re-run the installer to try the video again." >&2
    fi
    # Enable before anything touches tty1. Run from a login on the panel, this
    # script is hung up with that console below, and the next boot must still
    # start the kiosk.
    if ! sudo systemctl enable mcfly-display; then
        echo "mcfly-display could not be enabled yet; enable --now below tries again." >&2
    fi
    # Mask the console login on tty1. Conflicts= in the unit usually wins, but
    # if the kiosk is slow or exits once before DRM is ready, getty can paint
    # a login prompt and stay there. Masking leaves SSH as the way in; the
    # PI_SETUP recovery path unmasks when you want a local prompt. A mask
    # does not stop a prompt that is already up. The kiosk start below does
    # (Conflicts=) in the same transaction, so systemd still hands tty1 over
    # if that hangs up the login this script runs in. A failure here must not
    # skip the kiosk.
    sudo systemctl mask getty@tty1.service autovt@tty1.service 2>/dev/null || true
    # An older unit may have exhausted its start limit and will refuse --now
    # until that failure is cleared.
    sudo systemctl reset-failed mcfly-display || true
    if ! sudo systemctl enable --now mcfly-display; then
        echo "mcfly-display did not stay up on the first start. It stays enabled and will keep retrying." >&2
    fi
    if ! sudo systemctl restart mcfly-display; then
        echo "mcfly-display did not stay up yet. It will keep retrying, including on the next boot." >&2
    fi
fi
# kiosk-boot-end

# When updating, update the voice service too if it was installed before.
if [ -f /etc/systemd/system/mcfly-voice.service ]; then
    with_voice=1
fi
if [ "$with_voice" = "1" ]; then
    step "Installing the voice service"
    voice_args=()
    if [ "$skip_models" = "1" ]; then
        voice_args+=(--skip-models)
    fi
    if [ -f "$repo/voice/deploy/install-voice.sh" ]; then
        bash "$repo/voice/deploy/install-voice.sh" "${voice_args[@]}"
    else
        echo "voice/deploy/install-voice.sh not found; skipping the voice service" >&2
    fi
fi

step "Done"
# Bit 0 (now) or 16 (since boot) of get_throttled: the supply couldn't keep up.
throttled="$(vcgencmd get_throttled 2>/dev/null | sed -n 's/^throttled=//p' || true)"
if [[ "$throttled" =~ ^0x[0-9a-fA-F]+$ ]] && (( throttled & 0x10001 )); then
    echo "Warning: the Pi has been short of power since it started (throttled=$throttled)." >&2
    echo "Use the official 27 W USB-C supply, and power the panel from its own adapter." >&2
fi
# Bit 3 (now) or 19 (since boot): it reached its soft temperature limit and
# slowed down (to 1-1.5 GHz), which makes spoken replies late and halting.
# Only then is the fan worth a word. A Pi 5's device tree ships cooling_fan
# disabled and the firmware turns it on when it finds a fan on the FAN header
# at boot; a fan powered by something else (the screen's enclosure) isn't
# seen, and is fine as long as the Pi stays cool.
if [[ "$throttled" =~ ^0x[0-9a-fA-F]+$ ]] && (( throttled & 0x80008 )); then
    echo "Warning: the Pi has run too hot since it started (throttled=$throttled, $(vcgencmd measure_temp 2>/dev/null)), so it slowed down." >&2
    fan=""
    if [ -r /proc/device-tree/cooling_fan/status ]; then
        fan="$(tr -d '\0' < /proc/device-tree/cooling_fan/status)"
    fi
    if [ "$fan" = "disabled" ]; then
        echo "It sees no fan on its FAN header: fit the Active Cooler there, or check that a fan powered elsewhere cools it (docs/PI_SETUP.md)." >&2
    else
        echo "Check the Active Cooler and give the Pi some air (docs/PI_SETUP.md)." >&2
    fi
fi
if systemctl is-enabled --quiet mcfly-preview 2>/dev/null; then
    echo "Preview mode is on; the panel kiosk stays off."
else
    state="$(systemctl is-active mcfly-display 2>/dev/null || true)"
    echo "McFly is enabled and started. On every boot it takes HDMI (no login prompt)."
    echo "systemctl is-active mcfly-display: ${state:-unknown}"
    echo "active means the app has the panel. A terminal on the panel means it does not."
    echo "To put McFly on HDMI:  sudo systemctl enable --now mcfly-display"
    echo "Reboot so the console settings apply:  sudo reboot"
    echo "That reboot hides boot text and plays a short video until the app is up."
    if [ "$state" != "active" ]; then
        echo "The service is not active. Logs (these do not start the screen):" >&2
        echo "  journalctl -t mcfly-display -b --no-pager   what the app printed (no screen, QML errors)" >&2
        echo "  journalctl -u mcfly-display -b --no-pager   systemd's lines: why it did not start or stopped" >&2
    fi
fi
echo "On the screen, the gear icon changes Wi-Fi, speaker volume, and can restart or reboot."
echo "Logs only (does not start the screen):  journalctl -t mcfly-display -f"
if [ "$with_voice" = "1" ]; then
    echo "Voice logs:              journalctl -u mcfly-voice -f"
fi
