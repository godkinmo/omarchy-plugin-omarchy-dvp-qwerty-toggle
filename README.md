# Kanata Service Toggle for Omarchy

An Omarchy bar widget that toggles the two systemd **user** units behind the
Programmer Dvorak (DVP) + QWERTY overlay setup:

- `kanata.service` — the kanata keyboard remapper
- `kanata-layer-watcher.service` — the fcitx5-driven DVP/QWERTY layer switcher

One click starts both when stopped, or stops both when running, and the icon
reflects live status. It talks to `systemctl --user`, so no privilege
escalation is required.

## Requirements

The units must already exist. They are created by
`~/.dotfiles/bin/install-dvorak-programmer-qwerty.sh`, which installs the
kanata config and enables both units under `~/.config/systemd/user/`.

## Install

```bash
omarchy plugin add https://github.com/godkin/omarchy-plugin-omarchy-dvp-switcher.git --enable
```

Or, from a local checkout:

```bash
omarchy plugin add . --enable
```

Then place it in the bar if it did not land automatically:

```bash
omarchy bar move godkin.omarchy-dvp-qwerty-toggle --section right
```

## Usage

| Action | Result |
|--------|--------|
| Left click | Stop both units if both are active, otherwise start both |
| Hover | Tooltip shows `Kanata on` / `Kanata off` / `Kanata partial` / `Kanata: switching…` |
| IPC | `omarchy-shell kanata-service toggle` toggles from anywhere |

The widget can also be driven over IPC, so a keybinding can reuse it:

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER", "K", "omarchy-shell kanata-service toggle", "Toggle Kanata")
```

## Settings

Set these inline on the widget's entry in `~/.config/omarchy/shell.json`:

| Key | Default | Description |
|-----|---------|-------------|
| `refreshIntervalSec` | `5` | How often to poll unit status |
| `kanataUnit` | `kanata.service` | Main kanata unit |
| `watcherUnit` | `kanata-layer-watcher.service` | Layer watcher unit |

## Remove

```bash
omarchy plugin remove godkin.omarchy-dvp-qwerty-toggle
```

## License

MIT
