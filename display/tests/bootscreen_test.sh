#!/usr/bin/env bash
# The boot video, its player, and the handoff to the kiosk. No Pi or systemd:
# ffprobe reads the file when it is installed, a stand-in replaces ffplay, and the stop helper has to end the real player script.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
video="$root/display/deploy/boot/boot.mp4"
player="$root/display/deploy/boot/mcfly-bootscreen"
stop="$root/display/deploy/boot/mcfly-stop-bootscreen"
unit="$root/display/deploy/mcfly-bootscreen.service"
display="$root/display/deploy/mcfly-display.service"
install="$root/display/deploy/install-pi.sh"
quiet="$root/display/deploy/quiet-boot.sh"

fail() { printf 'bootscreen test failed: %s\n' "$1" >&2; exit 1; }

bash -n "$player" || fail "player script has a syntax error"
bash -n "$stop" || fail "stop helper has a syntax error"
bash -n "$install" || fail "install-pi.sh has a syntax error"

[ -f "$video" ] || fail "boot.mp4 is missing"
size=$(wc -c <"$video")
[ "$size" -gt 20000 ] || fail "boot.mp4 is too small ($size)"
[ "$size" -lt 2500000 ] || fail "boot.mp4 is too large ($size)"
# MP4 files carry 'ftyp' at byte 4.
magic=$(dd if="$video" bs=1 skip=4 count=4 2>/dev/null || true)
[ "$magic" = "ftyp" ] || fail "boot.mp4 is not an mp4"

if command -v ffprobe >/dev/null 2>&1; then
    probe=$(ffprobe -v error -show_entries stream=codec_type,codec_name,width,height -show_entries format=duration -of default=nw=1 "$video")
    printf '%s\n' "$probe" | grep -qx 'codec_name=h264' || fail "video is not h264"
    printf '%s\n' "$probe" | grep -qx 'width=1920' || fail "video is not 1920 wide"
    printf '%s\n' "$probe" | grep -qx 'height=1200' || fail "video is not 1200 tall"
    if printf '%s\n' "$probe" | grep -qx 'codec_type=audio'; then
        fail "boot video should be silent"
    fi
    dur=$(printf '%s\n' "$probe" | sed -n 's/^duration=//p' | head -1)
    awk -v d="$dur" 'BEGIN { exit !(d >= 4 && d <= 8) }' || fail "duration $dur is not a few seconds"
    if command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg -v error -i "$video" -frames:v 1 -f null - || fail "ffmpeg could not decode a frame"
    fi
fi

# Comments stripped so a note mentioning Conflicts= cannot satisfy a check.
unit_body() { sed -E 's/[[:space:]]+#.*$//; /^[[:space:]]*#/d' "$1"; }

unit_body "$unit" | grep -q 'ExecStart=/usr/local/libexec/mcfly-bootscreen' || fail "player unit has the wrong start"
unit_body "$unit" | grep -q 'Before=mcfly-display.service' || fail "video is not ordered before the app"
unit_body "$unit" | grep -q 'Before=.*getty@tty1.service' || fail "video does not precede getty"
unit_body "$unit" | grep -q 'Conflicts=.*getty@tty1.service' || fail "video does not keep getty off tty1"
if unit_body "$unit" | grep -q 'Conflicts=.*mcfly-display'; then
    fail "a conflict with the kiosk drops one of them from the boot transaction"
fi
if unit_body "$unit" | grep -Eq '^After=.*getty@'; then
    fail "After=getty lets the login prompt win"
fi

if unit_body "$unit" | grep -q 'network'; then
    fail "the boot video waits on the network"
fi
unit_body "$display" | grep -q 'ExecStartPre=-+/usr/local/libexec/mcfly-stop-bootscreen' || fail "kiosk does not stop the video first"
unit_body "$display" | grep -q 'After=mcfly-bootscreen.service' || fail "kiosk does not wait until the video has started"
if unit_body "$display" | grep -q 'Conflicts=.*mcfly-bootscreen'; then
    fail "kiosk conflicts with the video, so one of them will not start"
fi

# Quiet boot lives in quiet-boot.sh (kiosk_boot_test.sh runs it on sample
# files); the installer has to call it.
grep -Fq 'display/deploy/quiet-boot.sh' "$install" || fail "installer does not run quiet-boot.sh"
grep -q 'set_config_key disable_splash 1' "$quiet" || fail "quiet boot does not hide the rainbow splash"
for opt in quiet logo.nologo systemd.show_status=false loglevel=3 plymouth.enable=0; do
    grep -qx "    $opt" "$quiet" || fail "quiet boot does not set $opt"
done
grep -qx 'drop_options=(splash)' "$quiet" || fail "quiet boot does not drop the Plymouth splash"
grep -q 'ffmpeg curl' "$install" || fail "installer does not install ffmpeg and curl"
grep -q '/etc/mcfly/boot.mp4' "$install" || fail "installer does not document the custom video path"
grep -q 'enable mcfly-bootscreen' "$install" || fail "installer does not enable the video"
grep -q '99-mcfly-quiet.cfg' "$install" || fail "installer does not silence cloud-init logs"
grep -q 'cloud-final.service' "$install" || fail "installer does not override cloud-final"
grep -q 'StandardOutput=journal' "$install" || fail "installer does not take cloud-init off the console"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'not a video' >"$tmp/custom.mp4"
printf 'not a video' >"$tmp/installed.mp4"
# Keep the real display env and any cache on this machine out of the test.
export MCFLY_DISPLAY_ENV="$tmp/missing.env"
out=$(MCFLY_BOOTSCREEN_DRY_RUN=1 \
    MCFLY_BOOT_CUSTOM="$tmp/custom.mp4" \
    MCFLY_BOOT_INSTALLED="$tmp/installed.mp4" \
    "$player")
printf '%s\n' "$out" | grep -qx "video=$tmp/custom.mp4" || fail "custom video did not win"
rm -f "$tmp/custom.mp4"
out=$(MCFLY_BOOTSCREEN_DRY_RUN=1 \
    MCFLY_BOOT_CUSTOM="$tmp/custom.mp4" \
    MCFLY_BOOT_INSTALLED="$tmp/installed.mp4" \
    "$player")
printf '%s\n' "$out" | grep -qx "video=$tmp/installed.mp4" || fail "built-in video was not used"
# ffplay comes with ffmpeg on the Pi; a development machine may not have it.
if command -v ffplay >/dev/null 2>&1; then
    printf '%s\n' "$out" | grep -qx 'ffplay=1' || fail "dry run did not see ffplay"
fi
# A name with a space has to survive.
mkdir -p "$tmp/my video"
printf 'x' >"$tmp/my video/boot.mp4"
out=$(MCFLY_BOOTSCREEN_DRY_RUN=1 MCFLY_BOOT_VIDEO="$tmp/my video/boot.mp4" "$player")
printf '%s\n' "$out" | grep -qx "video=$tmp/my video/boot.mp4" || fail "video path with a space was split"

export MCFLY_BOOT_CUSTOM="$tmp/custom.mp4"
export MCFLY_BOOT_INSTALLED="$tmp/installed.mp4"
printf 'MCFLY_SUPABASE_URL="https://example.supabase.co"\nMCFLY_SUPABASE_ANON_KEY=test-anon-key\n' >"$tmp/display.env"
export MCFLY_DISPLAY_ENV="$tmp/display.env"

# Waiting for the network while the video plays. The resolve stand-in logs
# each host it is asked for, and succeeds once the "online" file exists.
cat >"$tmp/resolve" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >>"${MCFLY_RESOLVE_LOG:?}"
[ -e "${MCFLY_ONLINE:?}" ]
EOF
chmod +x "$tmp/resolve"
export MCFLY_BOOT_RESOLVE="$tmp/resolve"
export MCFLY_RESOLVE_LOG="$tmp/resolve.log"
export MCFLY_ONLINE="$tmp/online"
wait_online() { "$player" --wait-online 2>"$tmp/wait.log"; }

# No backend: nothing to wait for.
rm -f "$tmp/resolve.log" "$tmp/online"
MCFLY_DISPLAY_ENV="$tmp/missing.env" wait_online || fail "no backend failed the network wait"
[ ! -f "$tmp/resolve.log" ] || fail "waited for the network with no backend configured"

# The host is what gets resolved, whatever the URL around it.
: >"$tmp/online"
for pair in 'https://example.supabase.co|example.supabase.co' \
    'http://127.0.0.1:54321/|127.0.0.1' \
    'https://user@[::1]:8000/x|::1' \
    'https://example.supabase.co/?q=1|example.supabase.co'; do
    printf 'MCFLY_SUPABASE_URL=%s\nMCFLY_SUPABASE_ANON_KEY=k\n' "${pair%%|*}" >"$tmp/host.env"
    rm -f "$tmp/resolve.log"
    MCFLY_DISPLAY_ENV="$tmp/host.env" wait_online || fail "online network wait failed for ${pair%%|*}"
    [ "$(cat "$tmp/resolve.log")" = "${pair#*|}" ] || fail "resolved '$(cat "$tmp/resolve.log")' for ${pair%%|*}"
done
[ ! -s "$tmp/wait.log" ] || fail "an immediate network said it waited: $(cat "$tmp/wait.log")"

# The network comes up a moment later.
rm -f "$tmp/online" "$tmp/resolve.log"
( sleep 1.2; : >"$tmp/online" ) &
wait_online || fail "the network wait gave up although the network came up"
[ "$(wc -l <"$tmp/resolve.log")" -ge 2 ] || fail "the network wait did not try again"
grep -q 'network up after' "$tmp/wait.log" || fail "the network wait did not log how long it took"

# No network at all: give up after the limit, so the app opens offline.
rm -f "$tmp/online"
started=$SECONDS
if MCFLY_BOOT_NETWORK_WAIT=1 wait_online; then
    fail "the network wait reported a network that never came up"
fi
[ $((SECONDS - started)) -le 4 ] || fail "the network wait ran past its limit"
grep -q 'no network after 1 s' "$tmp/wait.log" || fail "the network wait did not log that it gave up"
started=$SECONDS
if MCFLY_BOOT_NETWORK_WAIT=0 wait_online; then
    fail "a wait of 0 reported a network that is down"
fi
[ $((SECONDS - started)) -le 2 ] || fail "a wait of 0 waited"

# The stop helper holds the video until the network is up...
sleep 30 &
pid=$!
MCFLY_BOOTSCREEN_PID=$pid "$stop" 2>/dev/null &
stopper=$!
sleep 1.5
kill -0 "$pid" 2>/dev/null || fail "stop helper took the video down before the network was up"
: >"$tmp/online"
for _ in $(seq 1 50); do
    kill -0 "$stopper" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$stopper" 2>/dev/null || kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$stopper" "$pid" 2>/dev/null || true
    fail "stop helper did not stop the video once the network was up"
fi
wait "$stopper" 2>/dev/null || true

# ...but with no video up (an app restart) it does not wait at all.
rm -f "$tmp/online" "$tmp/resolve.log"
true &
gone=$!
wait "$gone"
started=$SECONDS
MCFLY_BOOTSCREEN_PID=$gone "$stop"
[ ! -f "$tmp/resolve.log" ] || fail "stop helper waited for the network with no video up"
[ $((SECONDS - started)) -le 1 ] || fail "stop helper held an app restart"
: >"$tmp/online"

# The stop helper must end the player without asking systemd for a job.
sleep 30 &
pid=$!
MCFLY_BOOTSCREEN_PID=$pid "$stop"
if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
    fail "stop helper left the player running"
fi

# A player that takes a while to let go of the screen after TERM.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/ffplay" <<'EOF'
#!/bin/bash
printf '%s\n' "$$" >"${MCFLY_FAKE_PLAYER:?}.pid"
trap 'sleep 1; : >"$MCFLY_FAKE_PLAYER.exited"; exit 0' TERM
while :; do sleep 0.1; done
EOF
chmod +x "$tmp/bin/ffplay"
printf 'x' >"$tmp/clip.mp4"
# $1: seconds to play first. Over 1.5 s the wrapper is blocked in `wait`.
start_wrapper() {
    rm -f "$tmp/player.pid" "$tmp/player.exited"
    MCFLY_FAKE_PLAYER="$tmp/player" MCFLY_BOOT_VIDEO="$tmp/clip.mp4" \
        MCFLY_BOOT_TTY="$tmp/tty" MCFLY_BOOT_DRM_TRIES=0 PATH="$tmp/bin:$PATH" \
        "$player" &
    wrapper=$!
    for _ in $(seq 1 50); do
        [ -s "$tmp/player.pid" ] && break
        sleep 0.1
    done
    [ -s "$tmp/player.pid" ] || fail "the wrapper did not start the player"
    sleep "$1"
}
player_gone() {
    [ -f "$tmp/player.exited" ] && ! kill -0 "$(cat "$tmp/player.pid")" 2>/dev/null
}

# The wrapper on its own (what systemctl stop signals) exits only after the
# player has.
start_wrapper 2
kill -TERM "$wrapper"
wait "$wrapper" || true
player_gone || fail "the wrapper exited while the player still held the screen"

# The real wrapper and the stop helper, as the kiosk runs them: once the
# video has played a while (the usual boot), and right after it started.
for settle in 2 0.3; do
    start_wrapper "$settle"
    MCFLY_BOOTSCREEN_PID=$wrapper "$stop"
    if ! player_gone; then
        kill -KILL "$wrapper" "$(cat "$tmp/player.pid")" 2>/dev/null || true
        fail "stop helper returned while the player still held the screen ($settle s in)"
    fi
    if kill -0 "$wrapper" 2>/dev/null; then
        kill -KILL "$wrapper" 2>/dev/null || true
        fail "stop helper left the wrapper running ($settle s in)"
    fi
done

# A wrapper that dies at once and leaves its player behind: the helper still
# waits for the player, which is no longer under that pid.
rm -f "$tmp/player.pid" "$tmp/player.exited"
MCFLY_FAKE_PLAYER="$tmp/player" bash -c '"$1" & wait' _ "$tmp/bin/ffplay" &
orphaner=$!
for _ in $(seq 1 50); do
    [ -s "$tmp/player.pid" ] && break
    sleep 0.1
done
[ -s "$tmp/player.pid" ] || fail "the stand-in wrapper did not start the player"
MCFLY_BOOTSCREEN_PID=$orphaner "$stop"
[ -f "$tmp/player.exited" ] || fail "stop helper returned before an orphaned player exited"

echo "bootscreen ok"
