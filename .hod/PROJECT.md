# The intention of this project

This project is an Omarchy bar widget that installs and toggles the two systemd user units behind the Programmer Dvorak (DVP) plus QWERTY overlay setup: `kanata.service`, the kanata keyboard remapper, and `kanata-layer-watcher.service`, the fcitx5-driven DVP/QWERTY layer switcher. One switch starts both units or stops both, and the bar glyph shows live status. The project holds the kanata config, the watcher and the two units under `resources/`, and `resources/install.sh` writes them to `~/.config`. The toggle talks to `systemctl --user`, thus it needs no privilege escalation; the one root step, the package and the udev rule, runs in a terminal through `sudo`. The project is a package that a different developer installs with `omarchy plugin add`, and `Panel.qml` holds the whole widget.

Install the plugin with `omarchy plugin add . --enable`. A plugin install runs no hook, thus the user presses the Setup row in the popup or runs `resources/install.sh`. This project holds no dependency manifest and no test, thus it names no install command for dependencies, no test command and no start command.

- `.hod/` — the intention of the project and the rules of an agent
- `.agents/` — the skills that `hod` and this project give to a coding agent
- `.claude/` — the skills of the Claude Code client, which `.gitignore` holds
- `resources/` — the kanata config, the watcher, the two units and `install.sh`
- the top of the project — `Panel.qml`, the manifest `manifest.json` and `README.md`
