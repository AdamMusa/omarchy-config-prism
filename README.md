# Config Prism

[![Omarchy UI](https://img.shields.io/badge/built_with-Omarchy_UI-9bff73)](https://github.com/AdamMusa/omarchy-ui)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**See exactly how your live Omarchy configuration differs from the packaged defaults.**

Config Prism compares user-owned Omarchy and Hyprland files with the currently installed package defaults. It classifies modified, user-only, and newly packaged files without editing either side.

![Config Prism preview](preview.png)

## Built entirely in Ruby

All application behavior, system integration, and UI declarations are authored in
Ruby. There is no handwritten QML source. Omarchy UI compiles the Ruby-declared UI
into `OmarchyUI/Bundles/` and emits the tiny root QML loader shims required by the
plugin manifest; those shims are generated packaging output.

## Why this is distinct

Unlike configuration time machines, Config Prism compares the present configuration to the present Omarchy package baseline; it does not snapshot, restore, or overwrite files.

The concept was checked against the complete Omarchy Plugin Marketplace catalog before development.

## Install

```bash
omarchy plugin add https://github.com/AdamMusa/omarchy-config-prism.git --enable
```

The repository is self-contained. Omarchy UI asks Zui 0.0.10 to tree-shake the QML renderer at
bundle time, so users do not need Ruby or framework gems on the destination.

Review third-party plugin code before enabling it. Omarchy community plugins run with your user account.

## Use

Add **Config Prism** to the Omarchy bar and click its widget to open the panel. The plugin is keyboard-friendly, theme-aware, and designed for a 660 × 760 panel.

## Data, permissions, and safety

- Local state: `~/.local/state/omarchy-config-prism/state.json`
- State, command output, item counts, history, and rendered strings are bounded.
- State writes use an owner-only temporary file and atomic rename.
- System probes are read-only and invoke fixed argument arrays without a shell.

- No telemetry, analytics, remote account, package installation, or privileged command is used.
- The plugin never overwrites Omarchy, Hyprland, or application configuration.

External runtime tools are limited to standard commands already present on Omarchy when a feature needs them. Missing optional commands degrade to an explicit unavailable state. The exact commands are visible in [`lib/backend.rb`](lib/backend.rb).

## Remove

```bash
omarchy plugin remove izeesoft.config-prism
```

Removal leaves the local state file in place so reinstalling preserves history. To erase it too:

```bash
rm -r ~/.local/state/omarchy-config-prism
```

## Marketplace metadata

- Plugin ID: `izeesoft.config-prism`
- Category: System
- Tags: system, hyprland, quickshell
- Kinds: service, bar widget, panel
- Target: Omarchy Quattro on x86-64 Linux

## License

MIT.
