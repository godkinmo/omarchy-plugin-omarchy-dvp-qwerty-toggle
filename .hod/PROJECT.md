# The intention of this project

This project is an Omarchy bar widget that toggles the two systemd user units behind the Programmer Dvorak (DVP) plus QWERTY overlay setup: `kanata.service`, the kanata keyboard remapper, and `kanata-layer-watcher.service`, the fcitx5-driven DVP/QWERTY layer switcher. One switch starts both units or stops both, and the bar glyph shows live status. It talks to `systemctl --user`, thus it needs no privilege escalation. The project is a package that a different developer installs with `omarchy plugin add`, and `Panel.qml` holds the whole widget.

Install the plugin with `omarchy plugin add . --enable`. This project holds no dependency manifest and no test, thus it names no install command for dependencies, no test command and no start command. The units must exist before the plugin works; `~/.dotfiles/bin/install-dvorak-programmer-qwerty.sh` installs them.

- `.hod/` — the intention of the project and the rules of an agent
- `.agents/` — the skills that `hod` and this project give to a coding agent
- `.claude/` — the skills of the Claude Code client, which `.gitignore` holds
- the top of the project — `Panel.qml`, the manifest `manifest.json` and `README.md`
