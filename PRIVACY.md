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

The running app and bridge make no automatic or background network requests by default. There are no analytics, advertisements, crash reporters, or remote configuration services. The one exception is the update check: Settings → Updates → “Check” runs it on demand whenever the user clicks it, and if the user turns on the “Check automatically once a day” toggle in that same section, the same check also runs at most once every 24 hours, right after launch — never on a recurring background timer. Either way it sends a single unauthenticated `GET` to GitHub's public releases API (`api.github.com/repos/<owner>/barometer/releases/latest`) to read the latest tag name, and nothing else — no identifiers, no usage data, no credentials. Nothing is downloaded or installed automatically; a result only offers a link to the Releases page for the user to open themselves. Homebrew, the installer, and a direct release download access GitHub only to download source or a signed release archive for installation. On a fresh download, macOS's own Gatekeeper may independently perform a brief online check of the app's notarization ticket on first launch; this is a check macOS itself performs, not a request Barometer makes, and it does not recur on later launches.

## Local configuration

The app stores display, notification, and update-check preferences (including whether automatic checks are enabled and when one last ran) in macOS `UserDefaults`. Claude integration state and backups are stored under:

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
