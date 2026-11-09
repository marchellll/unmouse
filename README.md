# Unmouse

Menu-bar app that drives the pointer from the keyboard. A grid jumps to a point on screen, free mode steers the pointer and scroll, and hint mode labels the controls already on screen.

macOS 27. [MIT](LICENSE).

## Install

Download `Unmouse-<version>.zip` from [Releases](https://github.com/marchellll/unmouse/releases), unzip, and move `Unmouse.app` to `/Applications`.

Or build a signed copy from source. You need Swift 6.4 and an Apple Development certificate in the keychain.

```sh
git clone https://github.com/marchellll/unmouse.git
cd unmouse
./scripts/dev-app.sh
open Unmouse.app
```

The script writes `Unmouse.app` in the repo root and signs it with the first Apple Development identity it finds. Set `UNMOUSE_CODESIGN_IDENTITY` to pick a different one.

## Permissions

Unmouse has no Dock icon. Use the menu-bar icon, then **Settings…**.

The first launch walks through two permissions:

- **Accessibility** moves the pointer, clicks, scrolls, and reads on-screen controls for hint mode.
- **Input Monitoring** lets the event tap see the keys that open and drive each mode.

Both have to stay granted for the signed `Unmouse.app` you actually launch. A new signature is a different app to macOS, so grant them again after switching between a development build and a notarized one.

**Open at login** works for `Unmouse.app`. It does not register a bare `swift run` binary.

## Use

Tap a mode key. Hold it longer than the alone-tap limit (200 ms by default) and the key goes to the app underneath instead. Grid, free, and hint leave themselves after 10 seconds without a key. Change either limit in Settings.

| | Open | Then |
|---|---|---|
| Grid | Tap left ⌘ | Type a cell label. Space left-clicks. `a` right-clicks, `s` middle-clicks, `d` moves without clicking. Delete steps back, Tab moves to the next screen, Escape cancels. |
| Free | Tap left ⌥ | `j` `k` `l` `;` steer (arrows do the same). Hold `z` to go faster, `x` to go slower. `m` `,` `.` `/` scroll. `q` toggles a drag. Space left-clicks and stays in free mode. Escape cancels. |
| Hint | ⌘⇧Space | Type a label to arm that control. Space left-clicks it and leaves. `a` right-clicks, `d` moves without clicking, left ⌥ moves there and enters free mode. Delete steps back, Escape cancels. |

On a finished grid cell, left ⌥ moves there before entering free mode. Settings shows the full binding list and can record new shortcuts.

The menu-bar icon opens Settings and Quit. **Coach** lists what the current mode can do. **Tutorial** replays the install walkthrough or one practice session.

## Configuration

Settings write `~/Library/Application Support/unmouse/config.toml`. Editing that file reloads it. The first launch copies the bundled default and sizes the grid to the display under the pointer.

**Settings → Presets** replaces that file with a bundled layout: `default`, `azerty`, `colemak`, `colemak-dh`, `dvorak`, or `workman`.

Shortcut syntax is in the comments at the bottom of [`configs-example/default.config.toml`](configs-example/default.config.toml). One key, or modifiers plus one key joined by `+`. A value can be a list of shortcuts.

With **Karabiner** on (the default), Unmouse also reads [Karabiner-Elements](https://karabiner-elements.pqrs.org/)’ virtual keyboard, so mode keys still arrive while another app has Secure Input. Off uses the event tap only. Settings shows which path is live.

Logs go to Console under subsystem `xyz.marchell.unmouse`, category `app`. The level is in Settings. `none` writes nothing.

## Development

[Contributing](docs/contributing.md) covers the build. [Architecture](docs/architecture.md) is the map of the code. [Release](docs/release.md) covers signing, notarization, and the zip.
