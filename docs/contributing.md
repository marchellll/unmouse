# Contributing

Unmouse is a Swift package. `Unmouse` is the menu-bar app. `UnmouseCore` is the logic the tests cover. `Packages/BoundaryLabeling` places hint labels.

## Requirements

- macOS 27
- Swift 6.4 (`Package.swift` tools version is 6.4)
- An Apple Development certificate, to run `Unmouse.app`

`swift test` does not need a certificate. Launching the app does, because Accessibility and Input Monitoring stick to a stable signature. A new signature is a different app to macOS, so grant both again after switching between a development build and a notarized one.

## Where code goes

Logic that can run without AppKit belongs in `UnmouseCore`, with a test next to the other suites in `Tests/UnmouseCoreTests`. The app target is where events, windows, and permissions live.

The repo map is in [architecture.md](architecture.md#repo-layout).

## Build and run

```sh
swift build
swift test
swift test --package-path Packages/BoundaryLabeling
```

Run the app with the signed bundle, not `swift run`. **Open at login** registers `Unmouse.app` only. It does not register a bare `swift run` binary.

```sh
./scripts/dev-app.sh
open Unmouse.app
```

`dev-app.sh` signs with `UNMOUSE_CODESIGN_IDENTITY` when that is set, otherwise the first Apple Development identity in the keychain. It does not read `signing.env`. That file is for `scripts/release.sh`.

`Unmouse.app` and `dist/` are gitignored. So is `signing.env`. Leave certificates, `.p12` files, and notary passwords out of the repo. `signing.env.example` lists the variable names.

## Checks before a pull request

For a user-visible change, run `./scripts/dev-app.sh`, launch `Unmouse.app`, and try the mode you touched: open it, do the action, cancel, and confirm Settings still loads `config.toml`. Grid, free, and hint share the event path in `Sources/Unmouse/Input/NavigationModel.swift`, so a shortcut change is worth a pass through the other two modes. For a hint change, also type a text match, press ⌘1 after three characters, check a window row and an app row, and confirm Space and Return both activate.

Logs go to Console under subsystem `xyz.marchell.unmouse`. Input tracing always prints to stderr and to category `input`. The log level in Settings gates category `app`. `none` writes nothing there.
