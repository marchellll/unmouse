# Unmouse

Menu-bar app that drives the pointer from the keyboard. A grid jumps to a point on screen, free mode steers the pointer and scroll, and hint mode labels on-screen controls and fuzzy-searches text, menus, windows, and apps.

macOS 27. [MIT](LICENSE).

## Install

Download `Unmouse-<version>.dmg` from [Releases](https://github.com/marchellll/unmouse/releases), open it, and drag `Unmouse.app` to `Applications`.

Or with Homebrew:

```sh
brew trust marchellll/unmouse
brew install --cask marchellll/unmouse/unmouse
```

## Permissions

Unmouse has no Dock icon. Use the menu-bar icon, then **Settings…**.

The first launch walks through two permissions:

- **Accessibility** moves the pointer, clicks, scrolls, and reads on-screen controls, menus, windows, and text for hint mode.
- **Input Monitoring** lets Unmouse see the keys that open and drive each mode.

Leave both granted. Unmouse cannot move the pointer or see those keys without them.

## Use

Tap a mode key. Hold it longer than the alone-tap limit (200 ms by default) and the key goes to the app underneath instead. Grid, free, and hint leave themselves after 10 seconds without a key. Change either limit in Settings.

Focusing a window moves the pointer to that window's center when the pointer is outside it. A click inside the window stays put, and grid, free, and hint do not move it. **Center on focus** in Settings turns this off (`center_on_focus` in the config).

| | Open | Then |
|---|---|---|
| Grid | Tap left ⌘ | Type a cell label. `f`, Space, or Return left-clicks. `d` right-clicks, `s` middle-clicks. `r` holds a left click, `e` a right click, `w` a middle click, then drops into free mode so the drag can move. ⌘, ⌥, ⌃, or ⇧ on those keys is sent with the click. Delete steps back, Tab moves to the next screen, Escape cancels. |
| Free | Tap left ⌥ | `j` `k` `l` `;` steer (arrows do the same). Hold `z` to go faster, `x` to go slower. `m` `,` `.` `/` scroll. `f` clicks, `d` right-clicks, `s` middle-clicks. `r` `e` `w` toggle a held left, right, or middle button. The same four modifiers pass through. Space or Return also left-clicks. Escape cancels. |
| Hint | ⌘⇧Space | Type a label or search text, menus, windows, and apps. Space or Return activates the selection. Control+Space or Control+Return right-clicks. After 3 characters, ⌘1–⌘9 pick a top hit. Alone ⌘ opens the grid; alone ⌥ moves there and enters free mode. Delete edits the query, Escape cancels. ⌘Tab and other ⌘⌥⌃ chords leave hint and reach the system; ⌘T, ⌃Space, and ⌘1–9 stay. |

On a finished grid cell, left ⌥ moves there before entering free mode. Settings shows the full binding list and can record new shortcuts.

The menu-bar icon opens Settings and Quit. **Coach** lists what the current mode can do. **Tutorial** replays the install walkthrough or one practice session.

## Configuration

Settings write `~/Library/Application Support/unmouse/config.toml`. Editing that file reloads it. The first launch copies the bundled default and sizes the grid to the display under the pointer.

**Settings → Presets** replaces that file with a bundled layout: `default.config`, `azerty.example.config`, `colemak.example.config`, `colemak-dh.example.config`, `dvorak.example.config`, or `workman.example.config`.

Shortcut syntax is in the comments at the bottom of [`configs-example/default.config.toml`](configs-example/default.config.toml). One key, or modifiers plus one key joined by `+`. A value can be a list of shortcuts.

With **Karabiner** on (the default), mode keys still arrive while another app has Secure Input, such as a password field. Settings shows whether [Karabiner-Elements](https://karabiner-elements.pqrs.org/) is in use.

## Development

[Contributing](docs/contributing.md) covers the build. [Architecture](docs/architecture.md) is the map of the code. [Release](docs/release.md) covers signing, notarization, and the disk image.
