#!/usr/bin/env bash
# Moves the Pi 5's fan steps about 5 °C up, so the fan stays on its quieter
# steps for the same work. The firmware's steps are 50, 60, 67.5 and 75 °C
# (pwm 75, 125, 175, 250), each easing off 5 °C below where it came in. With
# the screen saver and the wake word the panel's Pi sat at 62-68 °C: past
# 67.5 the fan went to its third step, about 7,400 rpm, a hum across the
# room, and stayed there until the Pi was under 62.5. Here the steps are 55,
# 65, 72 and 78 °C at the same speeds: the Pi runs a few degrees warmer for
# it, under the 80 °C where it starts slowing itself (vcgencmd
# get_throttled), far from its 110 °C critical trip.
#
# The settings are a marked block of dtparams under [pi5] at the end of
# config.txt; other models don't have the fan. Safe to re-run: the block is
# rewritten in place, and nothing is printed when nothing changed. The
# original config.txt is kept once, as config.txt.mcfly-backup. --remove
# takes the block out again. Either takes effect after a reboot.
#
#   fan-steps.sh [--remove] [config.txt]
set -euo pipefail

remove=0
if [ "${1:-}" = "--remove" ]; then
    remove=1
    shift
fi
config="${1:-/boot/firmware/config.txt}"

if [ ! -f "$config" ]; then
    echo "$config not found (not a Raspberry Pi?); leaving the fan as it is"
    exit 0
fi

begin='# McFly: the fan steps 5 degrees up (display/deploy/fan-steps.sh)'
end='# McFly: end of the fan steps'

write_file() {
    local dest="$1"
    if [ -w "$dest" ]; then
        cat >"$dest"
    else
        sudo tee "$dest" >/dev/null
    fi
}

backup_once() {
    local src="$1"
    local dest="${src}.mcfly-backup"
    [ -f "$dest" ] && return 0
    if [ -w "$(dirname "$src")" ]; then
        cp -a "$src" "$dest"
    else
        sudo cp -a "$src" "$dest"
    fi
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
# Everything but this script's block and any other fan step settings (the
# steps are this block's to set), then the block at the end.
awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip = 1; next }
    skip && $0 == end { skip = 0; next }
    skip { next }
    /^[[:space:]]*dtparam=fan_temp[0-3](_hyst|_speed)?=/ { next }
    { print }
' "$config" >"$tmp"
if [ "$remove" -eq 0 ]; then
    {
        printf '%s\n' "$begin" '[pi5]'
        printf 'dtparam=%s\n' fan_temp0=55000 fan_temp1=65000 fan_temp2=72000 fan_temp3=78000
        printf '%s\n' '[all]' "$end"
    } >>"$tmp"
fi

if ! cmp -s "$tmp" "$config"; then
    backup_once "$config"
    write_file "$config" <"$tmp"
    if [ "$remove" -eq 1 ]; then
        echo "Took McFly's fan steps out of $config (the firmware's apply after a reboot)"
    else
        echo "Set the fan's steps to 55, 65, 72 and 78 °C in $config (takes effect after a reboot)"
    fi
fi
