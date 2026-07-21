# Barometer

Barometer is a private, open-source macOS menu bar monitor for Claude Code usage limits. It displays the 5-hour and 7-day usage percentages and their reset countdowns.

Barometer retains only limit percentages and reset times. It does **not** ask for your Claude credentials, OAuth token, cookies, API key, prompts, transcript, model details, context usage, token counts, cost, or working directory. It makes no network requests and includes no analytics.

Left-click the menu bar item for the usage panel. Right-click it for quick access to refresh, displayed metric, menu bar style, the optional reset countdown, notifications, launch at login, Claude Code connection, settings, and quit.

> Status: early development. Installing from a tagged release requires `v0.1.0` to be published; until then, build from source below.

## Requirements

- macOS 14 Sonoma or newer
- Claude Code with a Claude.ai Pro or Max subscription

Building from source instead of installing a release additionally requires Apple Command Line Tools or Xcode (`xcode-select --install`). See [Build from source](#build-from-source).

Claude Code only includes `rate_limits` after the first API response in a session. Barometer will show “No usage data yet” until that happens.

## Install

Tagged releases are signed with a Developer ID certificate and notarized by Apple, so no local build tooling is required:

```bash
brew install --cask yasinsimsek/tap/barometer
```

or a version-pinned release installer:

```bash
curl -fsSL https://github.com/yasinsimsek/barometer/releases/download/v0.1.0/install-v0.1.0.sh | bash
```

For a safer inspect-first curl flow:

```bash
curl -fsSLO https://github.com/yasinsimsek/barometer/releases/download/v0.1.0/install-v0.1.0.sh
less install-v0.1.0.sh
bash install-v0.1.0.sh
```

Both routes download an immutable tagged release archive, verify its SHA-256 checksum, and verify the app's notarization ticket before installing it to `~/Applications/Barometer.app`. Neither uses `sudo`. You can also grab the release `.dmg` or `.zip` directly from the [Releases page](https://github.com/yasinsimsek/barometer/releases): for the `.dmg`, open it and drag `Barometer.app` onto the `Applications` shortcut inside; for the `.zip`, unarchive it and drag `Barometer.app` into `~/Applications` yourself.

## Build from source

If you'd rather build Barometer yourself than trust a prebuilt binary, clone the repository, review the source, then run:

```bash
make test
make install
```

This builds Barometer on your Mac, applies a local ad-hoc signature (not the Developer ID signature tagged releases use), and installs it to `~/Applications/Barometer.app`. It never uses `sudo` and never disables Gatekeeper.

Do not run the installer with `sudo`. If `~/Applications` is not writable, repair that directory's ownership instead; the installer deliberately refuses root execution.

For development:

```bash
swift run BarometerApp
```

The packaged app is recommended for Claude Code integration because it contains the bridge helper at a stable location.

## How the Claude Code connection works

1. Barometer previews the proposed change and waits for explicit approval.
2. It backs up `~/.claude/settings.json` and replaces only its `statusLine` field.
3. Claude Code sends status-line JSON to the bundled `barometer-bridge` helper.
4. The helper allowlists only `rate_limits.five_hour` and `rate_limits.seven_day`. It discards every other field.
5. It merges samples by reset window under a cross-process lock, so an idle Claude session cannot overwrite a newer limit period. Expired windows display as zero until Claude sends the next sample.
6. It atomically writes a small `0600` cache file and runs your previous status-line command, if one existed.
7. Disconnect restores the previous `statusLine` only when the active value still exactly matches Barometer’s installation. User changes are never overwritten.

```text
Claude Code stdin JSON
        │
        ▼
barometer-bridge ─────► previous status-line command ─────► Claude Code UI
        │
        └── sanitized percentages + reset times
                         │
                         ▼
                  local 0600 cache
                         │
                         ▼
                  Barometer menu bar
```

See [PRIVACY.md](PRIVACY.md) and [THREAT_MODEL.md](THREAT_MODEL.md) for the exact data boundary.

## Uninstall

From a source checkout:

```bash
make uninstall
```

The command first restores the previous Claude Code status line and removes Barometer's validated per-user launch-at-login file. If restoration would overwrite a user change, it stops. On success, the app is moved to Trash rather than permanently deleted.

Homebrew Cask installations can be removed with:

```bash
brew uninstall --cask barometer
```

This runs the same `--prepare-uninstall` restoration step before removing the app. To also remove Barometer's local cache, settings backups, and launch-at-login file, use `brew uninstall --zap --cask barometer` instead.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Do not report vulnerabilities in public issues; follow [SECURITY.md](SECURITY.md).

Barometer is available under the [MIT License](LICENSE).
