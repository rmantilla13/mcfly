#!/usr/bin/env bash
# The kiosk must be enabled and started by install-pi.sh, and the unit must
# take tty1 from getty. No Pi or systemd required: the decision block in
# install-pi.sh is run against a fake systemctl and the pi-sim stub.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
unit="$root/display/deploy/mcfly-display.service"
pam="$root/display/deploy/mcfly-display.pam"
install="$root/display/deploy/install-pi.sh"
preview="$root/display/deploy/preview.sh"
preview_unit="$root/display/deploy/mcfly-preview.service"
stub="$root/display/deploy/pi-sim/systemctl-stub"

fail() { printf 'kiosk boot test failed: %s\n' "$1" >&2; exit 1; }

# Comments stripped so a note mentioning getty cannot satisfy a directive.
unit_body() { sed -E 's/[[:space:]]+#.*$//; /^[[:space:]]*#/d' "$unit"; }

directive() {
    unit_body | grep -Eq "$1" || fail "unit missing: $1"
}

directive '^Conflicts=.*getty@tty1\.service'
directive '^Conflicts=.*autovt@tty1\.service'
directive '^Before=.*getty@tty1\.service'
directive '^Before=.*autovt@tty1\.service'
if unit_body | grep -Eq '^After=.*getty@'; then
    fail "After=getty lets the login prompt win the boot transaction"
fi
if unit_body | grep -q 'network-online'; then
    fail "kiosk waits for the network, so the panel stays blank until Wi-Fi"
fi
directive '^StandardInput=tty$'
directive '^TTYPath=/dev/tty1$'
directive '^TTYReset=yes$'
directive '^TTYVHangup=yes$'
directive '^TTYVTDisallocate=yes$'
directive '^UtmpIdentifier=tty1$'
directive '^PAMName=mcfly-display$'
directive '^Restart=always$'
directive '^RestartSec=1$'
directive '^StartLimitIntervalSec=0$'
directive '^\[Install\]$'
directive '^WantedBy=multi-user\.target$'
directive '^Wants=user@@UID@\.service$'
directive '^After=user@@UID@\.service$'
directive '^After=systemd-udev-trigger\.service$'
directive '^Wants=systemd-logind\.service$'
directive '^Environment=XDG_RUNTIME_DIR=/run/user/@UID@$'
directive '^User=@USER@$'
directive '^ExecStart=/usr/local/bin/mcfly-display$'
directive '^SupplementaryGroups=video render input audio tty$'
directive '^Environment=QT_QPA_PLATFORM=eglfs$'
directive '^Environment=QT_QPA_EGLFS_INTEGRATION=eglfs_kms$'
directive '^Environment=QT_QPA_EGLFS_KMS_CONFIG=/etc/mcfly/kms.json$'
directive '^Environment=QT_QPA_EGLFS_ALWAYS_SET_MODE=1$'
if unit_body | grep -Eq '^After=.*network-online|^Wants=network-online'; then
    fail "waiting for network-online leaves the panel on the console"
fi

# Any account the installer is logged in as. The unit must not name a person.
filled="$(sed -e 's/@USER@/pi/g' -e 's/@UID@/1000/g' "$unit")"
printf '%s\n' "$filled" | grep -qx 'User=pi' || fail "User= was not substituted"
printf '%s\n' "$filled" | grep -qx 'Wants=user@1000.service' || fail "user manager unit was not substituted"
printf '%s\n' "$filled" | grep -qx 'After=user@1000.service' || fail "After=user@ was not substituted"
printf '%s\n' "$filled" | grep -qx 'Environment=XDG_RUNTIME_DIR=/run/user/1000' || fail "runtime dir was not substituted"
if printf '%s\n' "$filled" | grep -q '@USER@\|@UID@'; then
    fail "placeholder left after substitution"
fi

grep -q 'session[[:space:]]*required[[:space:]]*pam_systemd.so' "$pam" || fail "pam stack does not open a logind session"
grep -q 'auth[[:space:]]*required[[:space:]]*pam_permit.so' "$pam" || fail "pam stack must not ask for a password"

grep -Fq 'quiet-boot.sh' "$install" || fail "install script does not quiet the boot console"
# cloud-init's units print to the console (journal+console). Since cloud-init
# 24 the network stage is cloud-init-network.service: miss it and its line
# lands on the screen while the boot video starts.
cloud_loop=$(grep -E '^for unit in cloud-init-local\.service' "$install")
uncloud_loop=$(grep -E '^for unit in cloud-init-local\.service' "$root/display/deploy/uninstall-pi.sh")
for cloud_unit in cloud-init-local cloud-init-main cloud-init-network cloud-init cloud-config cloud-final; do
    printf '%s\n' "$cloud_loop" | grep -Fq " $cloud_unit.service" || fail "install script leaves $cloud_unit.service printing on the console"
    printf '%s\n' "$uncloud_loop" | grep -Fq " $cloud_unit.service" || fail "uninstall script leaves the $cloud_unit.service drop-in"
done
grep -Fq 's/@USER@/$user/g' "$install" || fail "install script dropped user substitution"
grep -Fq 's/@UID@/$uid/g' "$install" || fail "install script dropped uid substitution"
grep -q 'mcfly-display.pam' "$install" || fail "install script does not install the pam stack"
grep -q 'loginctl enable-linger' "$install" || fail "install script dropped linger"
grep -Fq 'systemctl start "user@${uid}.service"' "$install" || fail "install script does not start the user manager"
grep -q 'set-default multi-user.target' "$install" || fail "install script no longer forces the console target"
grep -Fq '/etc/ssh/sshd_config.d/mcfly.conf' "$install" || fail "install script dropped the sshd drop-in"
grep -Fq 'IPQoS cs0 cs0' "$install" || fail "install script dropped IPQoS cs0 cs0"
grep -Fq 'UseDNS no' "$install" || fail "install script dropped UseDNS no"
grep -Fq 'chmod 644 /etc/ssh/sshd_config.d/mcfly.conf' "$install" || fail "sshd drop-in is not mode 644"
grep -Fq 'systemctl reload ssh' "$install" || fail "install script does not reload ssh"
grep -Fq 'wifi.powersave = 2' "$install" || fail "install script dropped Wi-Fi power save"

grep -q 'Conflicts=mcfly-display.service' "$preview_unit" || fail "preview no longer conflicts with the kiosk"
grep -q 'disable --now mcfly-display' "$preview" || fail "preview on does not stop the kiosk"
grep -q 'enable --now mcfly-preview' "$preview" || fail "preview on does not enable itself"
grep -q 'disable --now mcfly-preview' "$preview" || fail "preview off does not disable itself"
grep -q 'enable --now mcfly-display' "$preview" || fail "preview off does not restore the kiosk"
grep -q 'restart mcfly-display' "$preview" || fail "preview off does not start the kiosk"

# The unit file is copied, then reloaded, then enabled.
unit_at="$(grep -n '/etc/systemd/system/mcfly-display.service' "$install" | head -1 | cut -d: -f1)"
reload_at="$(grep -n 'daemon-reload' "$install" | head -1 | cut -d: -f1)"
enable_at="$(grep -n 'enable --now mcfly-display' "$install" | head -1 | cut -d: -f1)"
[ -n "$unit_at" ] && [ -n "$reload_at" ] && [ -n "$enable_at" ] || fail "missing install, reload, or enable"
[ "$unit_at" -lt "$reload_at" ] && [ "$reload_at" -lt "$enable_at" ] || fail "unit must be installed and reloaded before enable"

block="$(awk '/# kiosk-boot-begin/,/# kiosk-boot-end/' "$install")"
[ -n "$block" ] || fail "kiosk boot block not found in install-pi.sh"
printf '%s\n' "$block" | grep -q 'systemctl enable --now mcfly-display' || fail "boot block does not enable and start the kiosk"
printf '%s\n' "$block" | grep -q 'systemctl restart mcfly-display' || fail "boot block does not reload a running kiosk"
printf '%s\n' "$block" | grep -q 'systemctl mask getty@tty1.service' || fail "boot block does not mask getty@tty1"
printf '%s\n' "$block" | grep -q 'systemctl mask.*autovt@tty1.service' || fail "boot block does not mask autovt@tty1"
# Enabled for boot first, then getty masked (so nothing restarts it), then
# the kiosk start takes tty1 from getty (Conflicts=) in one systemd job.
enable_only_at=$(printf '%s\n' "$block" | grep -nE 'systemctl enable mcfly-display(;| |$)' | head -1 | cut -d: -f1)
mask_at=$(printf '%s\n' "$block" | grep -n 'systemctl mask getty@tty1' | head -1 | cut -d: -f1)
now_at=$(printf '%s\n' "$block" | grep -n 'systemctl enable --now mcfly-display' | head -1 | cut -d: -f1)
[ -n "$enable_only_at" ] && [ -n "$mask_at" ] && [ -n "$now_at" ] \
    && [ "$enable_only_at" -lt "$mask_at" ] && [ "$mask_at" -lt "$now_at" ] \
    || fail "the kiosk must be enabled, then getty masked, before the kiosk starts"
# Stopping getty on its own hangs up a login on the panel (and an installer
# running in it) before anything has started the kiosk.
if printf '%s\n' "$block" | grep -q 'systemctl stop getty@tty1'; then
    fail "boot block stops getty before the kiosk start can take tty1"
fi
if printf '%s\n' "$block" | grep -q 'is-active'; then
    fail "boot block still starts the kiosk only when it is already active"
fi
grep -q 'mask getty@tty1.service' "$preview" || fail "preview off does not remask getty"
grep -q 'disable --now mcfly-bootscreen' "$preview" || fail "preview on leaves the boot video enabled"
grep -qE 'systemctl enable mcfly-bootscreen( |$)' "$preview" || fail "preview off does not bring the boot video back"
if grep -q 'enable --now mcfly-bootscreen' "$preview"; then
    fail "preview off starts the boot video over the app"
fi

# preview_on: is-enabled mcfly-preview succeeds. restart_rc: what `restart` returns.
# hangup=1: the first command that takes tty1 hangs up the console this runs
# on, which ends the script there (exit 129, as SIGHUP would).
run_block() {
    local log="$1" preview_on="$2" restart_rc="$3" enable_rc="${4:-0}" hangup="${5:-0}"
    : >"$log"
    systemctl() {
        printf '%s\n' "$*" >>"$log"
        if [ "$hangup" = 1 ]; then
            case "$*" in
                'enable --now mcfly-display'|'restart mcfly-display'|stop\ getty@tty1*) exit 129 ;;
            esac
        fi
        case "$1" in
            is-enabled)
                if [ "$preview_on" = 1 ]; then return 0; fi
                return 3
                ;;
            enable) return "$enable_rc" ;;
            restart) return "$restart_rc" ;;
            *) return 0 ;;
        esac
    }
    sudo() { "$@"; }
    # shellcheck disable=SC1090
    source /dev/stdin <<<"$block"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Not enabled yet (a fresh install, or a previous one that never enabled it).
run_block "$tmp/log" 0 0
grep -qx 'unmask mcfly-display' "$tmp/log" || fail "fresh install did not unmask"
grep -qx 'mask getty@tty1.service autovt@tty1.service' "$tmp/log" || fail "fresh install did not mask getty"
grep -qx 'enable --now mcfly-display' "$tmp/log" || fail "fresh install did not enable and start"
grep -qx 'restart mcfly-display' "$tmp/log" || fail "fresh install did not reload the kiosk"
grep -qx 'enable mcfly-display' "$tmp/log" || fail "fresh install did not enable the kiosk for boot"
grep -qx 'enable mcfly-bootscreen' "$tmp/log" || fail "fresh install did not enable the boot video"
if grep -qx 'enable --now mcfly-bootscreen' "$tmp/log"; then
    fail "fresh install started the boot video over the app"
fi
if grep -qx 'disable --now mcfly-display' "$tmp/log"; then
    fail "fresh install disabled the kiosk"
fi

# Already installed: enable again and restart so the new binary is what is on screen.
run_block "$tmp/log" 0 0
grep -qx 'enable --now mcfly-display' "$tmp/log" || fail "update did not enable and start"
grep -qx 'restart mcfly-display' "$tmp/log" || fail "update did not restart"

# The panel is not up yet, so the start command fails. The unit must still be
# enabled, and the installer must keep going (Restart= retries).
if ! run_block "$tmp/log" 0 1; then
    fail "a failed restart aborted the boot block"
fi
grep -qx 'enable --now mcfly-display' "$tmp/log" || fail "failed restart skipped enable"
grep -qx 'restart mcfly-display' "$tmp/log" || fail "failed restart skipped the start"

# enable --now itself failed. Still restart, and do not abort the installer.
if ! run_block "$tmp/log" 0 0 1; then
    fail "a failed enable --now aborted the boot block"
fi
grep -qx 'enable --now mcfly-display' "$tmp/log" || fail "failed enable was not attempted"
grep -qx 'restart mcfly-display' "$tmp/log" || fail "failed enable skipped the start"

# Run from a login on the panel: taking tty1 hangs up this script. The kiosk
# must already be enabled for the next boot, and getty masked.
( run_block "$tmp/log" 0 0 0 1 ) && fail "the hangup stand-in did not end the block"
grep -qx 'enable mcfly-display' "$tmp/log" || fail "a hung-up install left the kiosk disabled"
grep -qx 'mask getty@tty1.service autovt@tty1.service' "$tmp/log" || fail "a hung-up install left getty unmasked"
[ "$(tail -1 "$tmp/log")" = 'enable --now mcfly-display' ] || fail "something took tty1 before the kiosk start"

# Preview mode is what was enabled: leave the kiosk off.
run_block "$tmp/log" 1 0
grep -qx 'disable --now mcfly-display' "$tmp/log" || fail "preview mode did not keep the kiosk off"
grep -qx 'disable --now mcfly-bootscreen' "$tmp/log" || fail "preview mode left the boot video on"
if grep -q 'enable --now mcfly-display' "$tmp/log"; then
    fail "preview mode enabled the kiosk"
fi
if grep -qx 'restart mcfly-display' "$tmp/log"; then
    fail "preview mode started the kiosk"
fi

# pi-install CI uses this stub: nothing is enabled, so the block must enable and start.
# Drop the fake systemctl function so this run actually executes the stub.
unset -f systemctl
stubdir="$tmp/bin"
mkdir -p "$stubdir"
cp "$stub" "$stubdir/systemctl"
chmod +x "$stubdir/systemctl"
stub_out="$(
    sudo() { "$@"; }
    PATH="$stubdir:${PATH:-/usr/bin:/bin}"
    # shellcheck disable=SC1090
    source /dev/stdin <<<"$block" 2>&1
)" || fail "boot block failed under the systemctl stub"
printf '%s\n' "$stub_out" | grep -q 'systemctl enable --now mcfly-display' || fail "stub path did not enable and start"
printf '%s\n' "$stub_out" | grep -q 'systemctl restart mcfly-display' || fail "stub path did not reload the kiosk"
if printf '%s\n' "$stub_out" | grep -q 'systemctl disable.*mcfly-display'; then
    fail "stub path disabled the kiosk"
fi
printf '%s\n' "$stub_out" | grep -qE 'systemctl enable mcfly-display$' || fail "stub path did not enable the kiosk for boot"

grep -q 'NAutoVTs=0' "$install" || fail "installer does not stop logind from spawning a login on tty1"
grep -q 'QT_QPA_EGLFS_ALWAYS_SET_MODE=1' "$install" || fail "installer does not force Qt to set the HDMI mode"
grep -q 'ensure_display_env QT_QPA_EGLFS_KMS_CONFIG' "$install" || fail "installer does not repair a stale display.env"
# Comments stripped, as for the unit: the note above the package list names it too.
# A here-string, not a pipe: grep -q quits at the match, and under pipefail
# sed's SIGPIPE would fail the check.
grep -Eq '(^|[[:space:]])qt6-image-formats-plugins([[:space:]]|$)' \
    <<<"$(sed -E 's/[[:space:]]+#.*$//; /^[[:space:]]*#/d' "$install")" \
    || fail "installer does not install Qt's WebP plugin (qt6-image-formats-plugins), so News pictures in .webp don't show"
docs="$root/docs/PI_SETUP.md"
grep -q 'only shows logs' "$docs" || fail "docs do not say journalctl only shows logs"
grep -q 'sudo systemctl enable --now mcfly-display' "$docs" || fail "docs do not say how to put McFly on HDMI"
grep -q 'systemctl unmask getty@tty1.service autovt@tty1.service' "$docs" || fail "docs do not say how to get a login prompt back"
if grep -q 'should not need' "$docs"; then
    fail "docs still tell them not to start the kiosk"
fi

# PAMName= moves the app into session-N.scope, so journald files its lines
# there and `journalctl -u mcfly-display` shows only systemd's. Every place
# that says how to read the app's log names it with -t.
connect="$root/display/deploy/connect-backend.sh"
grep -q 'journalctl -t mcfly-display' "$unit" || fail "unit comment does not say how to read the app's lines"
grep -q 'journalctl -t mcfly-display -b' "$install" || fail "installer's not-active hint misses the app's lines"
grep -q 'journalctl -t mcfly-display -f' "$install" || fail "installer's log hint misses the app's lines"
grep -q 'journalctl -t mcfly-display' "$connect" || fail "connect-backend.sh does not show the app's lines"
grep -q 'journalctl -t mcfly-display' "$docs" || fail "docs do not say how to read the app's lines"
for f in "$unit" "$install" "$docs" "$connect"; do
    if grep -q 'journalctl -u mcfly-display -f' "$f"; then
        fail "$(basename "$f") follows -u mcfly-display, which never shows the app's lines"
    fi
    if grep -Eq 'journalctl -u mcfly-display.*McFly display:' "$f"; then
        fail "$(basename "$f") greps the app's lines out of -u mcfly-display"
    fi
done

pick="$(awk '/# kms-pick-begin/,/# kms-pick-end/' "$install")"
[ -n "$pick" ] || fail "hdmi pick function not found"
# shellcheck disable=SC1090
source /dev/stdin <<<"$pick"

sys="$(mktemp -d)"
out=$(mcfly_pick_hdmi "$sys")
printf '%s\n' "$out" | grep -qx '/dev/dri/card1' || fail "missing DRM nodes did not fall back to card1"
printf '%s\n' "$out" | grep -qx 'HDMI1' || fail "missing DRM nodes did not fall back to HDMI1"

mkdir -p "$sys/card1-HDMI-A-1" "$sys/card1-HDMI-A-2"
printf 'disconnected\n' >"$sys/card1-HDMI-A-1/status"
printf 'connected\n' >"$sys/card1-HDMI-A-2/status"
out=$(mcfly_pick_hdmi "$sys")
printf '%s\n' "$out" | grep -qx '/dev/dri/card1' || fail "connected HDMI-A-2 used the wrong card"
printf '%s\n' "$out" | grep -qx 'HDMI2' || fail "connected HDMI-A-2 was not Qt HDMI2"

printf 'connected\n' >"$sys/card1-HDMI-A-1/status"
out=$(mcfly_pick_hdmi "$sys")
printf '%s\n' "$out" | grep -qx 'HDMI1' || fail "HDMI0 (HDMI-A-1) did not win when both ports are connected"

printf 'disconnected\n' >"$sys/card1-HDMI-A-1/status"
printf 'disconnected\n' >"$sys/card1-HDMI-A-2/status"
out=$(mcfly_pick_hdmi "$sys")
printf '%s\n' "$out" | grep -qx 'HDMI1' || fail "panel-off fallback was not HDMI0"

rm -rf "$sys/card1-HDMI-A-1" "$sys/card1-HDMI-A-2"
mkdir -p "$sys/card0-HDMI-A-1"
printf 'connected\n' >"$sys/card0-HDMI-A-1/status"
out=$(mcfly_pick_hdmi "$sys")
printf '%s\n' "$out" | grep -qx '/dev/dri/card0' || fail "HDMI card index was pinned"
rm -rf "$sys"

quiet="$root/display/deploy/quiet-boot.sh"
[ -x "$quiet" ] || fail "quiet-boot.sh is not executable"

# A stock Pi cmdline: kernel text on tty1, Plymouth splash, no quiet options.
stock='console=serial0,115200 console=tty1 root=PARTUUID=abcd-02 rootfstype=ext4 fsck.repair=yes rootwait splash'
printf '%s\n' "$stock" >"$tmp/cmdline.txt"
printf '%s\n' '# comments stay' 'disable_splash=0' 'boot_delay=1' >"$tmp/config.txt"
"$quiet" "$tmp/cmdline.txt" "$tmp/config.txt" >"$tmp/quiet.out"
got="$(cat "$tmp/cmdline.txt")"
# Boot text goes to tty3, in place of tty1. tty1 is the VT the panel shows,
# and the last console= is /dev/console, so the VT keeps that role.
printf '%s\n' "$got" | grep -q '^console=serial0,115200 console=tty3 root=' || fail "kernel console did not move to tty3 in place"
if printf '%s\n' "$got" | grep -Eq '(^| )console=tty1( |$)'; then
    fail "boot text still lands on tty1, the panel"
fi
printf '%s\n' "$got" | grep -q 'root=PARTUUID=abcd-02' || fail "root device was dropped"
for opt in quiet loglevel=3 logo.nologo systemd.show_status=false plymouth.enable=0 consoleblank=0 vt.global_cursor_default=0; do
    printf '%s\n' "$got" | grep -Fq "$opt" || fail "cmdline missing $opt"
done
if printf '%s\n' "$got" | grep -Eq '(^| )splash( |$)'; then
    fail "Plymouth splash still starts"
fi
grep -qx 'disable_splash=1' "$tmp/config.txt" || fail "rainbow splash stays on"
grep -qx 'boot_delay=0' "$tmp/config.txt" || fail "firmware boot delay stays"
grep -qx 'boot_delay_ms=0' "$tmp/config.txt" || fail "firmware boot delay in ms stays"
grep -qx '# comments stay' "$tmp/config.txt" || fail "config.txt comments were dropped"
[ -f "$tmp/cmdline.txt.mcfly-backup" ] || fail "cmdline backup was not kept"
[ -f "$tmp/config.txt.mcfly-backup" ] || fail "config backup was not kept"

# Already quiet, including a duplicate and an old log level. Second run is a no-op.
printf '%s\n' 'console=tty1 quiet quiet loglevel=7 logo.nologo systemd.show_status=false consoleblank=0 vt.global_cursor_default=0' >"$tmp/cmdline2.txt"
printf '%s\n' 'disable_splash=1' 'boot_delay=0' 'boot_delay_ms=0' >"$tmp/config2.txt"
"$quiet" "$tmp/cmdline2.txt" "$tmp/config2.txt" >"$tmp/quiet2.out"
once="$(cat "$tmp/cmdline2.txt")"
printf '%s\n' "$once" | grep -q 'loglevel=3' || fail "old log level was kept"
if printf '%s\n' "$once" | grep -q 'loglevel=7'; then
    fail "old log level still present"
fi
# quiet once, not twice
quiet_count="$(printf '%s\n' "$once" | tr ' ' '\n' | grep -cx 'quiet' || true)"
[ "$quiet_count" -eq 1 ] || fail "quiet was duplicated ($quiet_count)"
backup_before="$(cat "$tmp/cmdline2.txt.mcfly-backup")"
"$quiet" "$tmp/cmdline2.txt" "$tmp/config2.txt" >"$tmp/quiet3.out"
[ "$(cat "$tmp/cmdline2.txt")" = "$once" ] || fail "second quiet-boot run rewrote cmdline"
[ ! -s "$tmp/quiet3.out" ] || fail "second quiet-boot run reported a change"
[ "$(cat "$tmp/cmdline2.txt.mcfly-backup")" = "$backup_before" ] || fail "second quiet-boot run replaced the backup"

# boot_delay must not rewrite boot_delay_ms, and a cmdline with no trailing
# newline (how some images ship it) still updates.
printf '%s' 'console=tty1 quiet splash plymouth.ignore-serial-consoles' >"$tmp/cmdline3.txt"
printf '%s' $'boot_delay_ms=5\n#keep\n' >"$tmp/config3.txt"
"$quiet" "$tmp/cmdline3.txt" "$tmp/config3.txt" >/dev/null
got3="$(cat "$tmp/cmdline3.txt")"
printf '%s\n' "$got3" | grep -Fq 'plymouth.ignore-serial-consoles' || fail "plymouth serial flag was dropped"
if printf '%s\n' "$got3" | grep -Eq '(^| )splash( |$)'; then
    fail "splash stayed on a Pi OS cmdline"
fi
grep -qx 'boot_delay=0' "$tmp/config3.txt" || fail "boot_delay was not set beside boot_delay_ms"
grep -qx '#keep' "$tmp/config3.txt" || fail "config comment beside boot_delay_ms was dropped"
# The ms key must stay the ms key. Matching boot_delay as a prefix would
# rewrite this line into boot_delay=0.
[ "$(head -1 "$tmp/config3.txt")" = "boot_delay_ms=0" ] || fail "boot_delay matched boot_delay_ms"

# Stock config.txt ends in model filters. A new key appended after [cm5]
# would only apply on a CM5, so it has to land above the first filter.
printf '%s\n' '# stock' 'dtparam=audio=on' '[cm4]' 'otg_mode=1' '[cm5]' 'dtoverlay=dwc2,dr_mode=host' '[all]' >"$tmp/config4.txt"
printf '%s\n' 'console=tty1' >"$tmp/cmdline4.txt"
"$quiet" "$tmp/cmdline4.txt" "$tmp/config4.txt" >/dev/null
filter_at="$(grep -n '^\[cm4\]' "$tmp/config4.txt" | cut -d: -f1)"
for key in disable_splash=1 boot_delay=0 boot_delay_ms=0; do
    key_at="$(grep -nx "$key" "$tmp/config4.txt" | head -1 | cut -d: -f1)"
    [ -n "$key_at" ] && [ "$key_at" -lt "$filter_at" ] || fail "$key landed inside a model filter"
done
grep -qx '\[all\]' "$tmp/config4.txt" || fail "config.txt filters were dropped"

# No VT console means the kernel default, tty1: add tty3. Several VT consoles
# become one tty3, where the first was. A serial console is not a VT.
printf '%s\n' 'root=PARTUUID=abcd-02 rootwait' >"$tmp/cmdline5.txt"
"$quiet" "$tmp/cmdline5.txt" "$tmp/config4.txt" >/dev/null
grep -Eq '(^| )console=tty3( |$)' "$tmp/cmdline5.txt" || fail "a cmdline with no console= kept boot text on tty1"
printf '%s\n' 'console=tty1 console=ttyAMA0,115200 console=tty2 root=PARTUUID=abcd-02' >"$tmp/cmdline6.txt"
"$quiet" "$tmp/cmdline6.txt" "$tmp/config4.txt" >/dev/null
got6="$(cat "$tmp/cmdline6.txt")"
printf '%s\n' "$got6" | grep -q '^console=tty3 console=ttyAMA0,115200 root=' || fail "serial console ttyAMA0 was treated as a VT"
vt_count="$(printf '%s\n' "$got6" | tr ' ' '\n' | grep -cE '^console=tty[0-9]+$' || true)"
[ "$vt_count" -eq 1 ] || fail "VT consoles were not folded into one tty3 ($vt_count)"

# No firmware files: the installer still finishes (a container, or not a Pi).
"$quiet" "$tmp/missing-cmdline.txt" "$tmp/missing-config.txt" >"$tmp/missing.out"
grep -q 'skipping console setup' "$tmp/missing.out" || fail "missing cmdline did not skip"

# The fan's steps (fan-steps.sh): about 5 °C above the firmware's, as a
# marked block of dtparams under [pi5] at the end of config.txt. The
# installer sets them; the uninstaller takes them out again.
fan="$root/display/deploy/fan-steps.sh"
[ -x "$fan" ] || fail "fan-steps.sh is not executable"
grep -Fxq '"$repo/display/deploy/fan-steps.sh"' "$install" || fail "install script does not set the fan's steps"
grep -Fxq '"$(dirname "$0")/fan-steps.sh" --remove' "$root/display/deploy/uninstall-pi.sh" || fail "uninstall script leaves the fan's steps"
stock_pi5=('# stock' 'dtparam=audio=on' 'arm_boost=1' '[cm4]' 'otg_mode=1' '[cm5]' 'dtoverlay=dwc2,dr_mode=host' '[pi5]' 'dtoverlay=nospi10' '[all]')
printf '%s\n' "${stock_pi5[@]}" >"$tmp/fan.txt"
cp "$tmp/fan.txt" "$tmp/fan.orig"
"$fan" "$tmp/fan.txt" >"$tmp/fan.out"
grep -q '55, 65, 72 and 78' "$tmp/fan.out" || fail "fan-steps.sh did not say what it set"
want_block=$'# McFly: the fan steps 5 degrees up (display/deploy/fan-steps.sh)\n[pi5]\ndtparam=fan_temp0=55000\ndtparam=fan_temp1=65000\ndtparam=fan_temp2=72000\ndtparam=fan_temp3=78000\n[all]\n# McFly: end of the fan steps'
[ "$(tail -n 8 "$tmp/fan.txt")" = "$want_block" ] || fail "the fan's steps are not the block under [pi5] at the end"
[ "$(head -n 10 "$tmp/fan.txt")" = "$(cat "$tmp/fan.orig")" ] || fail "fan-steps.sh changed the rest of config.txt"
cmp -s "$tmp/fan.txt.mcfly-backup" "$tmp/fan.orig" || fail "config.txt was not backed up before the fan's steps"
# Again: nothing to do, nothing said.
cp "$tmp/fan.txt" "$tmp/fan.once"
"$fan" "$tmp/fan.txt" >"$tmp/fan2.out"
cmp -s "$tmp/fan.txt" "$tmp/fan.once" || fail "a second fan-steps.sh run rewrote config.txt"
[ ! -s "$tmp/fan2.out" ] || fail "a second fan-steps.sh run reported a change"
# Fan steps set by hand give way to the block, wherever they were.
printf '%s\n' 'dtparam=fan_temp0=40000' '[pi5]' 'dtparam=fan_temp0_speed=90' 'dtparam=fan_temp1_hyst=2000' '[all]' >"$tmp/fan3.txt"
"$fan" "$tmp/fan3.txt" >/dev/null
[ "$(grep -c '^dtparam=fan_temp' "$tmp/fan3.txt")" -eq 4 ] || fail "hand-set fan steps were kept beside the block"
grep -qx 'dtparam=fan_temp0=55000' "$tmp/fan3.txt" || fail "the block did not replace a hand-set step"
# --remove puts config.txt back as it was, and says so once.
"$fan" --remove "$tmp/fan.txt" >"$tmp/fan4.out"
cmp -s "$tmp/fan.txt" "$tmp/fan.orig" || fail "fan-steps.sh --remove left something behind"
grep -q 'firmware' "$tmp/fan4.out" || fail "fan-steps.sh --remove did not say so"
"$fan" --remove "$tmp/fan.txt" >"$tmp/fan5.out"
[ ! -s "$tmp/fan5.out" ] || fail "a second --remove reported a change"
# Not a Pi (a container): nothing to set, and the installer goes on.
"$fan" "$tmp/missing-config.txt" >"$tmp/fan6.out"
grep -q 'leaving the fan as it is' "$tmp/fan6.out" || fail "a missing config.txt did not skip the fan"

echo "kiosk boot ok"
