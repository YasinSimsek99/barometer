# Contributing

Thanks for helping improve Barometer.

## Development setup

Requirements are macOS 14 or newer and Xcode (not just Command Line Tools — `swift test` needs Xcode's XCTest, which Command Line Tools alone does not ship).

```bash
make build
make test
scripts/build-app.sh
```

`make build`/`make test` point `DEVELOPER_DIR` at `/Applications/Xcode.app` automatically when `xcode-select` isn't already pointed there. If you invoke `swift build`/`swift test` directly instead, export `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` yourself first.

Run the packaged app from `.build/Barometer.app` when testing Claude Code integration so the helper path is stable.

## Pull requests

- Keep the running app and bridge free of network requests and third-party runtime dependencies.
- Never add logging of raw status-line JSON.
- Add tests for parser, settings, cache, or installer behavior changes.
- Treat all filesystem paths and Claude input as untrusted.
- Update `PRIVACY.md` and `THREAT_MODEL.md` when a data flow or trust boundary changes.
- Keep user-visible strings localizable.
- Run the full test and app assembly commands before requesting review.

Security-sensitive changes should be small and independently reviewable. Generated build products and real Claude settings must never be committed.

## Releasing

Maintainer-only. Tagged releases are signed with a Developer ID certificate and notarized before being published as a GitHub release (with a `.dmg` and a `.zip`), a Homebrew Cask, and a curl installer.

One-time setup:

1. Create a "Developer ID Application" certificate at [developer.apple.com](https://developer.apple.com/account/resources/certificates/list) (via a CSR generated in Keychain Access) and install it in your local login keychain.
2. Create an App Store Connect API key at [appstoreconnect.apple.com/access/api](https://appstoreconnect.apple.com/access/api) and download its `.p8` once.
3. Store notarization credentials locally: `xcrun notarytool store-credentials barometer-notary --key <path-to-.p8> --key-id <KEYID> --issuer <ISSUER_ID>`.

Local dry run, before ever cutting a real release:

```bash
scripts/build-app.sh
NOTARY_PROFILE=barometer-notary \
  scripts/notarize.sh .build/Barometer.app "Developer ID Application: Your Name (TEAMID)"
```

CI-triggered release: push a `vX.Y.Z` tag. `.github/workflows/release.yml` builds, signs, notarizes, staples, and publishes a GitHub release using these repository secrets/variables:

- `DEVELOPER_ID_CERTIFICATE_P12` (base64-encoded exported certificate) and `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8` (base64-encoded, the same App Store Connect API key as above)
- `CODESIGN_IDENTITY` as a repository **variable** (not a secret — it's just the identity string, e.g. `Developer ID Application: Your Name (TEAMID)`)

After a release publishes, copy the rendered Cask (`.build/release-assets/barometer.rb` in CI's output) into the separate `homebrew-tap` repository by hand; this is not automated.
