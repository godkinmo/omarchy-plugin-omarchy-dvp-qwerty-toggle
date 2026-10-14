#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="${PLUGIN_DIR}/resources"
KANATA_DIR="${HOME}/.config/kanata"
UNIT_DIR="${HOME}/.config/systemd/user"
UNITS=(kanata.service kanata-layer-watcher.service)
DESKTOP_USER="${SUDO_USER:-${USER}}"
UDEV_RULES="/etc/udev/rules.d/99-input.rules"
KANATA_BIN="/usr/bin/kanata_cmd_allowed"

step() { printf '\n\033[1;34m➜\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'TEXT'
usage: install.sh [--user-only|--root-only]

  --user-only   write the ~/.config files and enable both units
  --root-only   install the package, the groups and the udev rule
  --all         run --user-only, then --root-only through sudo
TEXT
}

desktop_home() { getent passwd "${DESKTOP_USER}" | cut -d: -f6; }

run_as_desktop_user() {
  local home
  home="$(desktop_home)"
  [[ -n "${home}" ]] || die "no home directory for [${DESKTOP_USER}]"
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "${DESKTOP_USER}" -- env HOME="${home}" USER="${DESKTOP_USER}" "$@"
  else
    sudo -u "${DESKTOP_USER}" env HOME="${home}" USER="${DESKTOP_USER}" "$@"
  fi
}

aur_helper() {
  command -v yay 2>/dev/null || command -v paru 2>/dev/null || true
}

install_package() {
  local pkg="$1" helper
  helper="$(aur_helper)"
  [[ -n "${helper}" ]] || die "no AUR helper found; install [kanata-bin] then run this again"
  if [[ "$(id -u)" -eq 0 ]]; then
    step "Building [${pkg}] as [${DESKTOP_USER}]: an AUR helper refuses to run as root"
    run_as_desktop_user "${helper}" -S --needed --noconfirm "${pkg}"
  else
    "${helper}" -S --needed --noconfirm "${pkg}"
  fi
}

link_kanata_config() {
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
}

write_units() {
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
  if ! systemctl --user restart "${UNITS[@]}"; then
    warn "the units are enabled but did not start; run the root step to install [kanata-bin]"
    return 0
  fi
  ok "kanata and the layer watcher are enabled and started"
}

install_user_files() {
  link_kanata_config
  write_units
}

grant_groups() {
  step "Granting the input and uinput groups"
  for grp in input uinput; do
    if ! id -nG "${DESKTOP_USER}" | grep -qw -- "$grp"; then
      warn "adding ${DESKTOP_USER} to the [${grp}] group"
      getent group "${grp}" >/dev/null 2>&1 || groupadd "${grp}"
      usermod -aG "${grp}" "${DESKTOP_USER}"
    fi
  done
  ok "group membership is set"
}

install_udev_rule() {
  step "Installing the udev rule for /dev/uinput"
  if [[ -e "${UDEV_RULES}" && ! -f "${UDEV_RULES}" ]]; then
    die "[${UDEV_RULES}] exists and is not a regular file; refusing to overwrite"
  fi
  if [[ ! -f "${UDEV_RULES}" ]] || ! grep -q 'KERNEL=="uinput"' "${UDEV_RULES}" 2>/dev/null; then
    printf 'KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"\n' > "${UDEV_RULES}"
    udevadm control --reload-rules
    udevadm trigger
    ok "udev rule installed"
  else
    ok "udev rule already present"
  fi
}

load_uinput() {
  if [[ ! -e /dev/uinput ]]; then
    warn "loading the uinput kernel module"
    modprobe uinput
  fi
  if [[ -e /dev/uinput && ! -w /dev/uinput ]]; then
    warn "log out and back in for the group change to reach /dev/uinput"
  fi
}

install_root_files() {
  step "Installing packages"
  command -v pacman >/dev/null 2>&1 || die "pacman not found; this script targets Arch-based distros such as Omarchy"
  if [[ ! -x "${KANATA_BIN}" ]] && ! pacman -Q kanata-bin >/dev/null 2>&1; then
    install_package kanata-bin
  fi
  [[ -x "${KANATA_BIN}" ]] || die "[${KANATA_BIN}] is missing after the package step"
  ok "kanata-bin is installed"

  grant_groups
  install_udev_rule
  load_uinput
}

case "${1:---all}" in
  --user-only) install_user_files; enable_units ;;
  --root-only) install_root_files ;;
  --all)
    install_user_files
    step "Requesting root privileges for the package and udev steps"
    exec sudo "$0" --root-only
    ;;
  -h|--help) usage ;;
  *) usage >&2; die "unknown option: [$1]" ;;
esac

ok "Done."
