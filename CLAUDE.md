# CLAUDE.md

Guidance for AI assistants working in this repository.

## What this is

**VolumeScroll** is a tiny macOS menu-bar app (no Dock icon, no window) that
changes the system output volume by scrolling over the menu bar, and toggles
mute on a middle-click. The entire app is a single Swift file built by a single
shell script — there is no Xcode project, package manager, or dependency tree.

- **Scroll up/down over the menu bar** → raise/lower volume. One mouse notch =
  one OS volume step (1/16). Trackpads / high-res wheels are smoothed.
- **Middle-click the menu bar** → mute/unmute. Devices without a hardware mute
  fall back to remembering the level, dropping to zero, and restoring it.
- The menu-bar glyph **dims** (alpha 0.4) when muted or fully silent.

## Layout

| File | Purpose |
| --- | --- |
| `VolumeScroll.swift` | The whole app — CoreAudio volume control, the menu-bar event tap, the menu-bar glyph, and the About window. |
| `build.sh` | Compiles with `swiftc` and assembles + ad-hoc-signs the `.app` bundle. |
| `VolumeScroll.icns` | App / About-window icon, copied into the bundle's Resources. |
| `VolumeScroll.png` | Logo used in the README. |
| `VolumeScroll.html` | Standalone preview/landing page for the app. |
| `README.md` | User-facing docs. |
| `LICENSE` | MIT. |

`build/` is the output directory and is git-ignored, along with `*.app/` and
`.DS_Store`.

## Build & run

```bash
./build.sh                       # compiles + packages build/VolumeScroll.app
open "build/VolumeScroll.app"     # launch it
```

There is **no test suite, linter, or CI**. Verification is manual: build, run,
and exercise scroll/middle-click over the menu bar. Note that `swiftc` and the
CoreAudio/Cocoa frameworks only exist on macOS, so the app cannot be compiled or
run in a Linux container — confirm Swift changes by reasoning about them, not by
building, when not on a Mac.

## Architecture (all in `VolumeScroll.swift`)

The file is organized into `MARK:` sections, top to bottom:

1. **`enum SystemVolume`** — stateless CoreAudio wrapper. Gets/sets the default
   output device's `kAudioDevicePropertyVolumeScalar` and `...Mute`. Always
   tries the master channel first, then falls back to per-channel (stereo)
   reads/writes. `muteIsSupported()` distinguishes hardware mute from the
   software fallback.
2. **`mouseIsOverMenuBar()`** — hand-rolled hit test with an *inclusive* top
   edge (the `+1` tolerance) because `CGRect.contains`/`NSMouseInRect` treat
   `maxY` as exclusive and leave a dead strip at the very top of the screen.
   Don't "simplify" this back to `.contains()`.
3. **`enum AppIcon`** — draws the menu-bar glyph from SVG path data as a
   **template image** so macOS tints it for light/dark mode automatically.
4. **`AboutWindowController`** — programmatic About window (no nibs/storyboards).
5. **`AppDelegate`** — owns the `NSStatusItem`, the `CGEvent` tap, and all the
   volume/mute state. Tunables live at the top (`step`, `invert`,
   `trackpadPointsPerStep`).
6. **Entry point** — manual `NSApplication` setup with
   `setActivationPolicy(.accessory)` (agent app).

### Key mechanics to preserve

- **Event tap** (`setupEventTap`): a session-level `CGEvent.tapCreate` listening
  for `scrollWheel`, `otherMouseDown`, `otherMouseUp`. The handler **consumes**
  (returns `nil`) events that occur over the menu bar so nothing underneath
  reacts, and passes everything else through. The handler also re-enables the
  tap on `tapDisabledByTimeout`/`tapDisabledByUserInput` — keep that.
- **Continuous vs. line scroll**: trackpads report continuous point deltas
  accumulated against `trackpadPointsPerStep`; classic mice report integer line
  counts (one notch per line). Both paths funnel through `adjustVolume(by:)`.
- **Mute fallback**: `preMuteVolume` is only used when the device lacks a
  hardware mute. Scrolling up clears it (and `SystemVolume.set` clears a real
  hardware mute when raising above zero), mirroring the hardware volume keys.
- **Accessibility permission** is mandatory — the event tap fails to create
  without it, which triggers `promptForAccessibility()`.

## Conventions

- **Single-file by design.** Prefer extending `VolumeScroll.swift` over adding
  files unless there's a strong reason. If you do split it, update `build.sh`
  (the `swiftc` invocation lists source files explicitly).
- Keep the existing `MARK:` section structure and the comment style: comments
  explain *why* (especially the non-obvious workarounds), not *what*.
- UI is built **programmatically** — no Interface Builder / SwiftUI.
- Frameworks are limited to Cocoa, CoreAudio, ApplicationServices. Avoid adding
  dependencies.
- Bundle metadata (version, identifier `com.local.VolumeScroll`, `LSUIElement`,
  `LSMinimumSystemVersion` 12.0) lives in the `Info.plist` heredoc inside
  `build.sh` — update version numbers there and in `VolumeScroll.html`/README if
  releasing.

## Git workflow

- Develop on the assigned feature branch; never push to `main` directly.
- Push with `git push -u origin <branch-name>`.
- Do not open a pull request unless explicitly asked.
- Commit messages: short, imperative, descriptive (e.g. "Add MIT license").
