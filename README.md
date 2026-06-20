# VolumeScroll

**Volume control from the menu bar.**

VolumeScroll is a tiny macOS menu-bar app (no Dock icon, no window) that lets you
change the system output volume by scrolling over the menu bar:

- **Scroll up / down over the menu bar** to raise or lower the volume. One mouse
  notch matches a single OS volume step (1/16); trackpads and high-resolution
  wheels are smoothed so the steps feel natural.
- **Middle-click the menu bar** to mute / unmute. If the output device has no
  hardware mute, the app remembers your level, drops to zero, and restores it on
  the next unmute.
- The menu-bar glyph **dims** whenever the system is muted or fully silent.

## Requirements

- macOS 12.0 or later
- **Accessibility permission** — the app watches scroll and click events over the
  menu bar, so on first launch it will ask you to enable it under
  *System Settings ▸ Privacy & Security ▸ Accessibility*. Enable VolumeScroll,
  then quit and relaunch.

## Download

You can download the the binary from [releases](https://github.com/basvcds/Volumescroll/releases).

## Building

Everything is built by a single script:

- [build.sh](build.sh) — compiles [VolumeScroll.swift](VolumeScroll.swift) with
  `swiftc`, assembles a `.app` bundle (Info.plist + [VolumeScroll.icns](VolumeScroll.icns)),
  and ad-hoc signs it so the Accessibility grant sticks across launches.

```bash
./build.sh
open "build/VolumeScroll.app"
```

The build output lands in `build/` (which is git-ignored).

## Project layout

| File | Purpose |
| --- | --- |
| [VolumeScroll.swift](VolumeScroll.swift) | The whole app — CoreAudio volume control, the menu-bar event tap, and the About window. |
| [build.sh](build.sh) | Compiles and packages the `.app`. |
| [VolumeScroll.icns](VolumeScroll.icns) | App / About-window icon. |
| [VolumeScroll.html](VolumeScroll.html) | Bundled preview page for the app. |

## Disclaimer

I set this project up mainly to familiarize myself with **Claude**, **VS Code**,
and **Git**. It is a learning exercise — there is **no guarantee** that this app
won't eat your pets. Use at your own risk. 🐾
