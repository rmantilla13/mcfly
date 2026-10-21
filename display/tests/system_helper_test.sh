#!/usr/bin/env bash
# The Wi-Fi helper must pass names through to nmcli without a shell, and must
# refuse anything that isn't a Wi-Fi change or a reboot.
set -euo pipefail

helper="$(cd "$(dirname "$0")/.." && pwd)/deploy/mcfly-system"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
log="$tmp/log"

cat > "$tmp/nmcli" << 'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$MCFLY_LOG"
for arg in "$@"; do
    printf 'ARG %s\n' "$arg" >> "$MCFLY_LOG"
done
# Turn down what the real nmcli turns down. `device wifi connect` takes only
# these options, each with a value (NetworkManager's src/nmcli/devices.c); a
# fake that took anything let `password-file` ship, which nmcli has never had.
if [ "${1:-}" = "--wait" ]; then
    shift 2
fi
if [ "${1:-}" = device ] && [ "${2:-}" = wifi ] && [ "${3:-}" = connect ]; then
    [ "$#" -ge 4 ] || { echo "Error: SSID or BSSID are missing." >&2; exit 2; }
    shift 4
    while [ "$#" -gt 0 ]; do
        case "$1" in
            password|wep-key-type|ifname|bssid|name|private|hidden)
                [ "$#" -ge 2 ] || { echo "Error: $1 argument is missing." >&2; exit 2; }
                shift 2
                ;;
            *)
                printf "Error: invalid extra argument '%s'.\n" "$1" >&2
                exit 2
                ;;
        esac
    done
fi
exit 0
EOF
cat > "$tmp/systemctl" << 'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$MCFLY_LOG"
exit 0
EOF
chmod 755 "$tmp/nmcli" "$tmp/systemctl"

export PATH="$tmp:$PATH"
export MCFLY_LOG="$log"

fail() { printf 'helper test failed: %s\n' "$1" >&2; exit 1; }

: > "$log"
"$helper" wifi-status >/dev/null
grep -q 'ARG radio' "$log" || fail "wifi-status did not ask for the radio"
grep -q 'ARG device' "$log" || fail "wifi-status did not ask for devices"

: > "$log"
"$helper" wifi-radio on
grep -qx 'ARG on' "$log" || fail "wifi-radio on was not passed through"
if "$helper" wifi-radio maybe >/dev/null 2>"$tmp/err"; then
    fail "wifi-radio accepted a bad value"
fi
grep -q 'need on or off' "$tmp/err"

: > "$log"
if ! printf '%s' 'correct horse' | "$helper" wifi-connect 'Cafe:Bar' psk 2>"$tmp/err"; then
    fail "joining with a password failed: $(cat "$tmp/err")"
fi
grep -q 'ARG Cafe:Bar' "$log" || fail "SSID was not passed through intact"
# nmcli takes a Wi-Fi password only as the word after `password`.
grep -A1 -x 'ARG password' "$log" | grep -qx 'ARG correct horse' \
    || fail "password was not given to nmcli as its password"

# Spaces at either end and a leading dash are part of a password.
: > "$log"
if ! printf '%s' ' -dash and spaces ' | "$helper" wifi-connect 'Home' psk 2>"$tmp/err"; then
    fail "a password with a leading dash failed: $(cat "$tmp/err")"
fi
grep -A1 -x 'ARG password' "$log" | grep -qx 'ARG  -dash and spaces ' \
    || fail "a password with spaces at its ends or a leading dash was changed"

: > "$log"
if "$helper" wifi-connect '-sneaky' psk >/dev/null 2>"$tmp/err"; then
    fail "SSID starting with a dash was accepted"
fi
grep -q "isn't usable" "$tmp/err"
[ ! -s "$log" ] || fail "nmcli ran for a rejected SSID"

: > "$log"
if printf '%s\n' 'secret' | "$helper" wifi-connect "$(printf 'bad\nname')" psk >/dev/null 2>"$tmp/err"; then
    fail "SSID with a newline was accepted"
fi

# A name that looks like shell must stay a name.
: > "$log"
payload='$(touch /tmp/hos-pwn)'
printf '%s' 'pw' | "$helper" wifi-connect "$payload" psk
[ ! -e /tmp/hos-pwn ] || fail "SSID was executed by a shell"
grep -q "ARG $payload" "$log" || fail "shell-looking SSID was not passed literally"

: > "$log"
"$helper" wifi-connect 'Home' saved
grep -q 'ARG connection' "$log" || fail "saved network did not bring the profile up"
grep -q 'ARG Home' "$log" || fail "saved SSID missing"

: > "$log"
"$helper" reboot
grep -qx 'systemctl reboot' "$log" || fail "reboot did not call systemctl reboot"
if "$helper" reboot now >/dev/null 2>"$tmp/err"; then
    fail "reboot accepted an argument"
fi

echo "mcfly-system helper ok"
