# Release

`scripts/release.sh` reads `CFBundleShortVersionString` in `Support/Info.plist`. When that version is already tagged, it bumps the patch number until the tag is free, then increments `CFBundleVersion`. It builds a release binary, wraps it as `Unmouse.app`, signs it, and writes `dist/Unmouse-<version>.dmg`. The disk image holds `Unmouse.app` and an `Applications` link for drag-to-install. With a Developer ID Application certificate and a notarytool keychain profile, it signs, notarizes, and staples the disk image, then commits the plist, tags `v<version>`, and pushes the tag.

## One-time setup

1. Install a **Developer ID Application** certificate in the login keychain. An Apple Development certificate can build a disk image, and the script will say it is local-only and skip notarization.
2. Store notary credentials in the keychain. The profile name defaults to `notarytool`.

```sh
xcrun notarytool store-credentials notarytool
```

3. Optional. Copy the example and set identities when you do not want the first match in the keychain:

```sh
cp signing.env.example signing.env
```

`signing.env` is gitignored. `scripts/release.sh` sources it. The variables it reads:

| Variable | Use |
|---|---|
| `UNMOUSE_DEVELOPER_ID_IDENTITY` | `Developer ID Application: …` identity. When this is set, or when that kind of identity is in the keychain, the script notarizes. |
| `UNMOUSE_CODESIGN_IDENTITY` | `Apple Development: …` identity, used when no Developer ID is available. |
| `UNMOUSE_NOTARY_PROFILE` | notarytool keychain profile. Default `notarytool`. |

## Cut a release

1. Run the tests:

```sh
swift test
swift test --package-path Packages/BoundaryLabeling
```

2. Start from a clean working tree:

```sh
./scripts/release.sh
```

With the plist at `0.1.0` and tag `v0.1.0` already there, this ships `0.1.1`. Set `CFBundleShortVersionString` to a new minor or major first when that is the version to ship; the script keeps it when that tag does not exist yet. Output is `dist/Unmouse-<version>.dmg`, next to `dist/Unmouse.app`.

It checks the notary profile before building. After a successful staple and `spctl` assessment it writes the version into `Support/Info.plist`, commits that file as `release: v<version>`, pushes `HEAD`, tags `v<version>`, and pushes the tag to `origin`. A missing profile, a failed notarization, or a failed assessment leaves `Support/Info.plist` unchanged.

3. Open `dist/Unmouse.app`, grant Accessibility and Input Monitoring for that signature, and confirm grid, free, and hint each open.

4. Update [`Casks/unmouse.rb`](https://github.com/marchellll/homebrew-unmouse) in the Homebrew tap. Set `version`, `sha256` from `shasum -a 256 dist/Unmouse-<version>.dmg`, and the asset suffix to `.dmg`. Attach the disk image to the GitHub Release for the tag.

An Apple Development certificate still produces the disk image. That path leaves `Support/Info.plist` and git unchanged.
