# Unmouse

Keep SOLID and KISS. Smallest change that stays correct. No extra abstraction.

## Settings and config stay equal

A behavior a person would reasonably want to change belongs in Settings (`Sources/Unmouse/Views/Settings/SettingsView.swift`).

Every Settings control has a key in `config.toml`, and every user-facing config key has a Settings control. Same knobs, same coverage. The schema is `Sources/UnmouseCore/Config/Config.swift`. The live file is `~/Library/Application Support/unmouse/config.toml`. The shipped copies are `configs-example/*.config.toml`.

Add the field, the Settings control, and the key in every example file together. A setting that exists in only one of those places is unfinished.

## Example configs

`configs-example/` has one file per layout:

- `default.config.toml`
- `azerty.example.config.toml`
- `colemak.example.config.toml`
- `colemak-dh.example.config.toml`
- `dvorak.example.config.toml`
- `workman.example.config.toml`

A new or changed non-binding key goes in all of them. Leave existing `[bindings.*]` alone unless the change is about those bindings.

## Docs

A user-visible change updates `README.md` and the doc that covers it: `docs/architecture.md`, `docs/contributing.md`, or `docs/release.md`. Do this in the same change as the code.
