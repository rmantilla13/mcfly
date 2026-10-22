#!/usr/bin/env bash
# Removes everything install-pi.sh (and install-voice.sh) put on this Pi, so
# a re-install starts from nothing: the services, the app, the system helper,
# the config in /etc/mcfly, the display's pairing, the voice service and its
# models. The Pi itself (Wi-Fi, your user, SSH) is left as it is.
#
#   ./display/deploy/uninstall-pi.sh                 # asks before it starts
#   ./display/deploy/uninstall-pi.sh --yes           # no question
#   ./display/deploy/uninstall-pi.sh --keep-models   # keep the ~220 MB of voice models
#
# Then, for a clean install:
#   cd ~ && rm -rf ~/mcfly && git clone https://github.com/rmantilla13/mcfly.git
#   cd mcfly && ./display/deploy/install-pi.sh --with-voice && sudo reboot
set -euo pipefail

if [ "$(uname -s)" != Linux ]; then
    echo "This runs on the Raspberry Pi. Log in to it first (ssh <user>@mcfly.local)." >&2
    exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your normal user; it uses sudo where needed." >&2
    exit 1
fi

yes=0
keep_models=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y) yes=1 ;;
        --keep-models) keep_models=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

if [ "$yes" != 1 ]; then
    echo "This removes McFly from this Pi: the app, its services and settings, its pairing"
    echo "with your account, and the voice service. Wi-Fi, your user and SSH stay."
    read -rp "Remove McFly? [y/N] " answer
    case "$answer" in y|Y|yes|YES) ;; *) echo "Nothing changed."; exit 0 ;; esac
fi

step() { printf '\n==> %s\n' "$1"; }

step "Stopping McFly"
for unit in mcfly-display mcfly-bootscreen mcfly-voice mcfly-preview; do
    sudo systemctl disable --now "$unit" 2>/dev/null || true
    sudo systemctl unmask "$unit" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/$unit.service"
done
for unit in cloud-init-local.service cloud-init-main.service cloud-init-network.service cloud-init.service cloud-config.service cloud-final.service; do
    sudo rm -f "/etc/systemd/system/${unit}.d/mcfly-quiet.conf"
    sudo rmdir "/etc/systemd/system/${unit}.d" 2>/dev/null || true
done
# The console login comes back on the panel.
sudo systemctl unmask getty@tty1.service autovt@tty1.service 2>/dev/null || true
sudo systemctl daemon-reload

step "Removing the app"
sudo rm -f /usr/local/bin/mcfly-display
sudo rm -f /usr/local/libexec/mcfly-system /usr/local/libexec/mcfly-bootscreen /usr/local/libexec/mcfly-stop-bootscreen
sudo rm -rf /usr/local/share/mcfly
sudo rm -f /etc/sudoers.d/mcfly-system /etc/pam.d/mcfly-display

step "Removing settings and pairing"
sudo rm -rf /etc/mcfly /var/lib/mcfly
# QSettings: the pairing session, the device id and the on-screen choices.
rm -rf "$HOME/.config/McFly"
sudo rm -f /etc/systemd/logind.conf.d/mcfly.conf /etc/ssh/sshd_config.d/mcfly.conf
sudo rm -f /etc/NetworkManager/conf.d/mcfly-wifi-powersave.conf /etc/cloud/cloud.cfg.d/99-mcfly-quiet.cfg
sudo rm -f /etc/wireplumber/wireplumber.conf.d/50-mcfly.conf /etc/wireplumber/wireplumber.conf.d/51-mcfly-speakers.conf
if [ -f /etc/asound.conf ] && grep -q 'McFly' /etc/asound.conf; then
    sudo rm -f /etc/asound.conf
fi

step "Removing the voice service"
sudo rm -rf /opt/mcfly-voice
if [ "$keep_models" != 1 ]; then
    rm -rf "$HOME/.local/share/mcfly-voice"
fi

sudo systemctl reload ssh 2>/dev/null || true
echo
echo "McFly is removed. The kernel's quiet-boot options stay (they only hide boot text,"
echo "and send what is left to tty3); /boot/firmware/cmdline.txt.mcfly-backup is the original."
echo "Install again with:"
echo "  cd ~ && rm -rf ~/mcfly && git clone https://github.com/rmantilla13/mcfly.git"
echo "  cd mcfly && ./display/deploy/install-pi.sh --with-voice && sudo reboot"
