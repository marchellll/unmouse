# Release

`scripts/release.sh` reads `CFBundleShortVersionString` in `Support/Info.plist`. When that version is already tagged, it bumps the patch number until the tag is free, then increments `CFBundleVersion`. It builds a release binary, wraps it as `Unmouse.app`, signs it, and writes `dist/Unmouse-<version>.dmg`. The disk image holds `Unmouse.app` and an `Applications` link for drag-to-install. With a Developer ID Application certificate and a notarytool keychain profile, it signs, notarizes, and staples the disk image, then commits the plist, tags `v<version>`, and pushes the tag.

An Apple Development certificate still produces the disk image. That path skips notarization and leaves `Support/Info.plist` and git unchanged.

## New Mac

Same Apple ID. The Developer ID Application `.p12` is the thing to import. The `.cer` alone cannot sign.

1. Double-click the `.p12` and enter the password set when it was exported. It lands in the login keychain.
2. Confirm the identity. The team id to use below is the one in parentheses on this line, not the one on an Apple Development identity:

```sh
security find-identity -p codesigning -v | grep "Developer ID Application"
```

3. At appleid.apple.com, create an app-specific password under Sign-In and Security. Then store notary credentials. Choose the Apple ID option, not an API key. Profile name `notarytool`. Team id is the one from the command above.

```sh
xcrun notarytool store-credentials notarytool
xcrun notarytool history --keychain-profile notarytool
```

`No submission history` means the credentials saved. Each Mac stores this itself. The `.p12` does not carry it.

`signing.env` is optional and gitignored. Copy `signing.env.example` only to pin an identity instead of the first match in the keychain.

## Cut a release

Release from one Mac at a time. Pull first so a version another Mac already shipped is not reused:

```sh
git pull --ff-only
swift test
swift test --package-path Packages/BoundaryLabeling
```

Working tree must be clean. Set `CFBundleShortVersionString` first when shipping a new minor or major. Otherwise the script keeps the plist version, or bumps the patch when that tag already exists.

```sh
./scripts/release.sh
```

It checks the notary profile before building. After a successful staple and `spctl` assessment it writes the version into `Support/Info.plist`, commits that file as `release: v<version>`, pushes `HEAD`, tags `v<version>`, and pushes the tag. The last line before the release path is the DMG's sha256. A missing profile, a failed notarization, or a failed assessment leaves `Support/Info.plist` unchanged.

Open `dist/Unmouse.app`, grant Accessibility and Input Monitoring for that signature, and confirm grid, free, and hint each open.

Publish the DMG, then point the [Homebrew cask](https://github.com/marchellll/homebrew-unmouse) at it. In `Casks/unmouse.rb`, set `version` and paste the sha256 the script printed. The URL already ends in `.dmg`.

```sh
gh release create v<version> dist/Unmouse-<version>.dmg --repo marchellll/unmouse --title "Unmouse <version>"
```

Push the cask, then:

```sh
brew fetch --cask marchellll/unmouse/unmouse
```
