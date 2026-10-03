#!/usr/bin/env bash
#
# install.sh -- install the kanata side of the Programmer Dvorak (DVP) +
# QWERTY overlay setup, from the files that ship inside this plugin.
#
#   ./install.sh --user-only   write ~/.config files and enable both units
#   ./install.sh --root-only   install packages, groups, the udev rule
#   ./install.sh               run --user-only, then --root-only through sudo
#
# The plugin's Setup button runs --user-only first, then opens a terminal that
# runs --root-only, so the password prompt stays in a terminal that the user
# can see.
set -euo pipefail

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="${PLUGIN_DIR}/resources"
KANATA_DIR="${HOME}/.config/kanata"
UNIT_DIR="${HOME}/.config/systemd/user"
UNITS=(kanata.service kanata-layer-watcher.service)

step() { printf '\n\033[1;34m➜\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

in_groups() { id -nG | grep -qw -- "$1"; }

ensure_group() { getent group "$1" >/dev/null 2>&1 || groupadd "$1"; }

aur_install() {
  if command -v yay >/dev/null 2>&1; then
    yay -S --needed --noconfirm "$1"
  elif command -v paru >/dev/null 2>&1; then
    paru -S --needed --noconfirm "$1"
  else
    die "no AUR helper found; install [kanata-bin] then run this again"
  fi
}

install_user_files() {
  step "Linking kanata config into ${KANATA_DIR}"
  mkdir -p "${KANATA_DIR}"
  ln -sf "${RESOURCES}/dvp-qwerty.kbd" "${KANATA_DIR}/dvp-qwerty.kbd"
  ln -sf "${RESOURCES}/dvorak-qwerty.kbd" "${KANATA_DIR}/dvorak-qwerty.kbd"
  if [[ ! -e "${KANATA_DIR}/active.kbd" ]]; then
    ln -sf "${KANATA_DIR}/dvp-qwerty.kbd" "${KANATA_DIR}/active.kbd"
  fi
  ln -sf "${RESOURCES}/kanata-layer-watcher.sh" "${KANATA_DIR}/kanata-layer-watcher.sh"
  chmod +x "${RESOURCES}/kanata-layer-watcher.sh"
  ok "kanata config linked"

  step "Writing systemd user units into ${UNIT_DIR}"
  mkdir -p "${UNIT_DIR}"
  for unit in "${UNITS[@]}"; do
    sed "s|@HOME@|${HOME}|g" "${RESOURCES}/systemd/${unit}" > "${UNIT_DIR}/${unit}"
    chmod 644 "${UNIT_DIR}/${unit}"
  done
  ok "systemd units written"
}

enable_units() {
  step "Enabling and starting the units"
  systemctl --user daemon-reload
  systemctl --user enable "${UNITS[@]}"
  systemctl --user restart "${UNITS[@]}"
  ok "kanata and the layer watcher are enabled and started"
}

install_root_files() {
  step "Installing packages"

  if ! command -v pacman >/dev/null 2>&1; then
    die "pacman not found; this script targets Arch-based distros such as Omarchy"
  fi

  if [[ ! -x /usr/bin/kanata_cmd_allowed ]] && ! pacman -Q kanata-bin >/dev/null 2>&1; then
    aur_install kanata-bin
  fi
  ok "kanata-bin is installed"

  step "Granting the input and uinput groups"
  for grp in input uinput; do
    if ! in_groups "$grp"; then
      warn "adding ${USER} to the [${grp}] group"
      ensure_group "$grp"
      usermod -aG "$grp" "$USER"
    fi
  done
  ok "group membership is set"

  step "Installing the udev rule for /dev/uinput"
  udev_rules="/etc/udev/rules.d/99-input.rules"
  if [[ -e "${udev_rules}" && ! -f "${udev_rules}" ]]; then
    die "[${udev_rules}] exists and is not a regular file; refusing to overwrite"
  fi
  if [[ ! -f "${udev_rules}" ]] || ! grep -q 'KERNEL=="uinput"' "${udev_rules}" 2>/dev/null; then
    printf 'KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"\n' \
      > "${udev_rules}"
    udevadm control --reload-rules
    udevadm trigger
    ok "udev rule installed"
  else
    ok "udev rule already present"
  fi

  if [[ ! -e /dev/uinput ]]; then
    warn "loading the uinput kernel module"
    modprobe uinput
  fi

  if [[ -e /dev/uinput && ! -w /dev/uinput ]]; then
    warn "log out and back in for the group change to reach /dev/uinput"
  fi
}

case "${1:---all}" in
  --user-only) install_user_files; enable_units ;;
  --root-only) install_root_files ;;
  --all)
    install_user_files
    step "Requesting root privileges for the package and udev steps"
    exec sudo "$0" --root-only
    ;;
  *) die "usage: install.sh [--user-only|--root-only]" ;;
esac

ok "Done."
