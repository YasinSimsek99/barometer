# Threat Model

## Scope and assets

Barometer protects Claude Code settings, status-line input, local usage data, and the user’s existing status-line command. The local macOS user and reviewed Barometer releases are trusted. A fully compromised user account or operating system is out of scope.

## Trust boundaries

1. Claude Code passes a potentially large and sensitive JSON document to the bridge over stdin.
2. The bridge writes a reduced cache consumed by the menu bar app.
3. The integration manager updates one field in `~/.claude/settings.json`.
4. Installation tooling downloads source code, or a signed release archive, from GitHub before local compilation or installation.
5. Tagged releases are signed with a Developer ID certificate and verified by Apple's notary service; the CI release job holds the signing certificate and notarization credentials only for the duration of that job.

## Threats and mitigations

| Threat | Mitigation |
| --- | --- |
| Credentials or prompts leak into cache/logs | Allowlist parser creates a new data model containing only rate-limit percentages and reset times; sentinel tests inspect persisted bytes; production code does not log status-line input. |
| Malformed or oversized status input exhausts resources | Bridge caps stdin at 2 MiB, rejects malformed/non-object JSON, finite/range-checks percentages, and preserves the previous valid cache. |
| Shell injection through status JSON | JSON input is passed through an anonymous pipe and is never interpolated into a shell command. |
| Existing status-line command is lost | Full original `statusLine` value and settings backup are stored with `0600` permissions; the old command is chained after capture. |
| Barometer overwrites a concurrent user edit | A content hash is checked before commit; disconnect uses exact structural equality and stops on conflict. |
| Symlink redirects writes to another file | Settings, state, cache, and managed directories reject symbolic-link endpoints. Writes use temporary files in the destination directory and atomic rename. |
| Other local users read usage or backups | Managed directories use `0700`; files use `0600`. |
| Downloaded installer/source/release is replaced | Release-specific installers and the Homebrew Cask pin both the download URL and a SHA-256 checksum of the release archive. |
| Downloaded prebuilt binary is tampered with in transit or at rest on GitHub | Tagged releases are notarized and stapled; the installer and Cask verify the checksum, and macOS/Gatekeeper independently verifies the stapled notarization ticket offline before the app is allowed to run. |
| Installer weakens platform security | Installers do not use root privileges, remove quarantine attributes, or alter Gatekeeper settings. |
| A source-built update changes its ad-hoc code identity | This applies only to source builds (`make install`), which are not notarized. The app bundle uses a stable identifier-only designated requirement. This is not a trust certificate; it only keeps local macOS service registration consistent across locally built updates. Tagged releases are signed with a real Developer ID identity instead, whose default designated requirement is anchored to Apple's certificate chain and Team ID and needs no such workaround. |
| Launch-at-login configuration is redirected or replaced | The per-user LaunchAgent path rejects symlinks, validates its label before overwrite/removal, uses an explicit executable path, and is written with `0600` permissions. |
| Local data is erased by a script or a second person at the keyboard without the device owner's consent | "Erase All Local Data" is gated by `LAPolicy.deviceOwnerAuthentication` (Touch ID or the account password) evaluated on-device via LocalAuthentication; the erase only proceeds after that policy succeeds. |
| Dependency or CI compromise | There are no runtime package dependencies; CI actions are pinned to full commit SHAs and receive read-only permissions except the tag-only release job. |
| Signing certificate or notarization credentials are leaked or stolen | The release job imports the certificate into a keychain created fresh for that job run and always deletes it afterward; notarization uses a revocable App Store Connect API key rather than an Apple ID password; credentials are only ever present as encrypted CI secrets or in the maintainer's local keychain, never committed or logged. |

## Known limitations

- Claude Code’s `rate_limits` exists only for supported Claude.ai subscriptions and only after an API response.
- Data becomes stale when Claude Code is closed or idle; Barometer marks it stale after ten minutes.
- Claude Code does not expose a credit balance or per-model quota through status-line data. Barometer does not infer either value; 5-hour and 7-day percentages remain account-level limits.
- Two distribution models coexist with different trust properties. Source builds (`make install`) are unsigned by Apple; users trust reviewed source, their own local toolchain, and GitHub transport. Tagged releases (GitHub Releases, Homebrew Cask, the curl installer) are signed with a Developer ID certificate and notarized; users additionally trust the maintainer's certificate custody and Apple's notary service, but need not trust their own build toolchain.
- On a fresh, previously untrusted download, Gatekeeper may still perform a brief online check of the notarization ticket on first launch even though the ticket is stapled; this is macOS's own first-launch behavior, not a network request made by Barometer itself, and does not recur on subsequent launches.
- The previous status-line command is intentionally executed through the same shell mechanism Claude Code used before Barometer. Barometer neither creates nor sanitizes that user-owned command.
