# Privacy

Barometer processes Claude Code usage data locally.

## Data processed

The bridge reads the JSON Claude Code sends to its configured status-line command. From that input it retains only:

- 5-hour usage percentage and reset time, when present;
- 7-day usage percentage and reset time, when present;
- the local capture timestamp;
- the cache schema version.

The cache is stored at:

```text
~/Library/Caches/io.github.yasinsimsek.barometer/usage.json
```

Its directory mode is `0700` and file mode is `0600`.

## Data never retained

Barometer does not retain Claude credentials, cookies, API keys, account identifiers, prompts, responses, session identifiers, model names or identifiers, context-window usage, transcript paths, repository paths, working directories, token counts, or costs.

## Network and third parties

The running app and bridge make no network requests. There are no analytics, advertisements, crash reporters, remote configuration services, or automatic updaters. Homebrew, the installer, and a direct release download access GitHub only to download source or a signed release archive for installation. On a fresh download, macOS's own Gatekeeper may independently perform a brief online check of the app's notarization ticket on first launch; this is a check macOS itself performs, not a request Barometer makes, and it does not recur on later launches.

## Local configuration

The app stores display preferences and notification state in macOS `UserDefaults`. Claude integration state and backups are stored under:

```text
~/Library/Application Support/io.github.yasinsimsek.barometer/
```

The integration backup may contain the user’s pre-existing Claude Code settings because it exists to support safe restoration. It is protected with local-only permissions and is never transmitted.

When “Launch at login” is enabled, Barometer writes a per-user LaunchAgent containing only its bundle identifier and the absolute path to its executable:

```text
~/Library/LaunchAgents/io.github.yasinsimsek.barometer.plist
```

Barometer logs connection, permission, and error state through Apple’s unified logging system. It never logs Claude Code status-line input, prompts, responses, credentials, usage payloads, or filesystem contents.

## Deleting your data

Settings → Data → “Erase All Local Data” disconnects Claude Code (restoring the previous status line when one exists), then deletes the usage cache and all settings backups. It is gated by macOS's local device-owner authentication (Touch ID or the account password) so the data cannot be erased by a script or a second person at the keyboard without proof of identity; this check runs entirely on-device through Apple's LocalAuthentication framework and involves no network request. Display preferences and notification state in `UserDefaults` are not affected, since they hold no Claude usage data.
