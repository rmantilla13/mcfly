#!/usr/bin/env bash
# Pictures of every screen at every panel size, from the demo data, for a
# layout review (and the docs). Builds first unless --no-build.
#
#   display/scripts/screenshots.sh [out-dir] [--no-build]
#
# Sizes: the 10.1" panel at scale 1.5 (1280x800), an HDMI monitor or TV
# (1920x1080), the 7" Touch Display (800x480) and the Touch Display 2 in
# portrait (720x1280). Screens: the --screen names the app takes. Needs the
# Qt the app was built with; on a Mac, CMAKE_PREFIX_PATH=/opt/homebrew/opt/qt.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${1:-$root/build/screenshots}"
build=1
for arg in "$@"; do
    [ "$arg" = --no-build ] && build=0
done
if [ "$build" = 1 ]; then
    cmake -S "$root/display" -B "$root/build/display" -DCMAKE_BUILD_TYPE=Release \
        ${CMAKE_PREFIX_PATH:+-DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH"} >/dev/null
    cmake --build "$root/build/display" --target mcfly-display -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)" >/dev/null
fi
app="${MCFLY_SHOT_APP:-$root/build/display/mcfly-display}"
mkdir -p "$out"
sizes="${MCFLY_SHOT_SIZES:-1280x800 1920x1080 800x480 720x1280}"
screens="${MCFLY_SHOT_SCREENS:-home briefs markets news projects boards calendar setup saver ask settings}"
export QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=Basic
for size in $sizes; do
    for screen in $screens; do
        file="$out/$screen-$size.png"
        if "$app" --demo --windowed --no-keyboard --size "$size" --screen "$screen" --screenshot "$file" \
            >"$out/$screen-$size.log" 2>&1; then
            echo "ok    $file"
        else
            echo "FAIL  $screen at $size (see $out/$screen-$size.log)"
        fi
    done
done
