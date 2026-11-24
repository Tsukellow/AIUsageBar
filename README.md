# AIUsageBar

A macOS menu bar app for checking **Claude, Codex, Antigravity, Grok, and DeepSeek usage** without keeping their dashboards open.

## Features

- Independent tracking and display settings for each provider: drop-down only, or menu bar and drop-down. The app keeps a menu entry even when no provider uses the menu bar.
- **Settings → General → Menu Bar** can hide the numbers beside all menu-bar rings. Usage details in the drop-down are unchanged.
- Each provider has its own menu-bar ring color, with a default and a restore button. The Settings sidebar uses locally packaged [provider icons](Artwork/ProviderIcons/SOURCES.md).
- Claude and Codex usage windows and reset information when available from the provider.
- Antigravity's five-hour and weekly quota pools and Grok's subscription window, with reset times when reported. Grok prepaid credits are separate from its included subscription quota.
- DeepSeek balance tracking with preset full-ring amounts (¥5–¥1000) and low-balance warnings (1%–20%). Settings update the menu bar immediately.
- Local Codex usage summaries and recent activity.
- Configurable refresh interval, startup delay, ring colors, and launch at login.

Provider data describes different things: subscription usage windows, local activity, and API balance are not interchangeable billing totals. This is an independent utility; provider dashboard endpoints and local file formats can change.

## Requirements

- macOS 14 or later.
- Xcode with a Swift 6 toolchain selected (`xcode-select -p`).
- An existing account/session for each provider you enable.

## Build from source

```sh
git clone https://github.com/Tsukellow/AIUsageBar.git
cd AIUsageBar
swift test
./scripts/build-app.sh --unsigned
```

The unsigned build packages `.build/unsigned/AI Usage Bar.app` from the checked-in source and assets. It does not need the local signing identity or any provider credentials. For a local signed install, use `./scripts/build-app.sh --signed` (the default), which packages, signs and verifies `.build/AI Usage Bar.app`. The signed mode needs Python 3. Quit the running app before replacing it, and keep the signed app at `/Applications/AI Usage Bar.app` before enabling **Launch at login**.

### Fixed local signing

AI Usage Bar and Pomodoro Clock share **Tsukellow Local Code Signing**. Each app keeps its own bundle identifier. The public certificate fingerprint is pinned in `scripts/signing-identity.json`; builds fail if the identity is missing, expired, or different. They never fall back to ad-hoc signing.

The private certificate, keychain, password file, and encrypted PKCS#12 backup are stored in `~/Library/Application Support/Tsukellow-Code-Signing/`, outside these repositories. The directory is owner-only (0700), and private files are 0600. Preserve and securely back up this entire directory. On another Mac, restore the existing identity and its user-domain code-signing trust instead of creating a new one. This is a local self-signed identity, without Apple Developer ID or notarization.

`scripts/local-signing.py init` is an explicit one-time setup command. It creates an identity only when no signing material or repository pin exists, or pins an existing shared identity for another app. It refuses to replace an existing identity. The trust applies to code signing only; the default login keychain and TLS trust are unchanged.

The first identity change may require renewed notification or login-item approval. Permission retention across future updates remains to be checked during normal use.

### App icon

The editable icon is `Artwork/AppIconSource.svg`; keep its checked-in 1024 px PNG export, `Artwork/AppIconSource.png`, in sync after artwork edits. During packaging, `scripts/render-icon.swift` applies the shared macOS tile and writes the generated previews and `AppIcon.icns` under `.build/generated-artwork/`.

## First-time setup

Open Settings from the menu bar panel and enable the providers you use:

| Provider | Configuration |
|---|---|
| Claude | Supply your own Claude web-session Cookie in the Claude settings section. Follow the instructions shown there. |
| Codex | Sign in through Codex first. The app reads local Codex data and authentication under `~/.codex/`. |
| Antigravity | Sign in through `agy`, enable tracking, choose **Connect Status Line**, then open a new CLI session. The app does not replace an existing custom status line. **Claude and GPT Models** is drop-down only by default. In **Tracking and display**, hide that pool or give it its own purple menu bar ring independently of Gemini Models. Desktop-only sessions do not update the snapshot. |
| Grok | Install the [Grok Build CLI](https://docs.x.ai/build/overview) and sign in through `grok login` with the subscription account. Enable Grok tracking. If the executable is not found automatically, select it in Settings. |
| DeepSeek | Supply your own DeepSeek platform session token in the DeepSeek settings section. This is a dashboard session credential, not an inference API key. |

Use **Refresh Now** to check each connection. Expired sessions may require signing in again and updating the configured credential. A failed refresh is not evidence of zero usage.

DeepSeek shows **Unavailable** when a daily or monthly cost is not reported or could not be read. An explicitly reported zero still appears as **¥0.00**.

## Usage links and balance warnings

The Codex panel opens `https://chatgpt.com/settings/usage`.

In DeepSeek settings, **Full ring balance** selects ¥5, ¥10, ¥20, ¥30, ¥50, ¥100, ¥200, ¥500, or ¥1000. **Low balance warning** selects 1%, 2%, 3%, 4%, 5%, 10%, or 20%. A balance at or below the full-ring amount times the warning percentage shows an exclamation mark. The default warning is 10%. Existing non-preset amounts remain available when opening the settings; upgrades preserve their exact values.

## Local data and credentials

Claude Cookie and DeepSeek token settings are currently stored in macOS `UserDefaults`, **not Keychain**. Codex authentication is read from its local configuration. Enabled providers are contacted to retrieve their usage data.

Antigravity uses the official [CLI status line callback](https://antigravity.google/docs/cli/statusline/). AI Usage Bar saves only recognized quota windows, reset times and the snapshot time under `~/.gemini/antigravity-cli/ai-usage-bar/`. It does not start the CLI, query Google, or read credentials. Turning tracking off stops capture and clears the snapshot. A snapshot is marked stale after 30 minutes or when one of its reported windows resets. Grok Build manages its own login; AI Usage Bar only sends the read-only billing request to the CLI's ACP interface, with no API-key or browser fallback.

Treat session credentials as passwords: do not include them in screenshots, issues, sample configuration, or commits. Clear a provider's configured credential when you no longer use it.

## Source map

- [AppDelegate.swift](Sources/AIUsageBar/AppDelegate.swift): menu bar item and windows.
- [CombinedMenuContentView.swift](Sources/AIUsageBar/CombinedMenuContentView.swift): combined provider panel.
- [SettingsView.swift](Sources/AIUsageBar/SettingsView.swift): connection and display settings.
- [CodexUsageService.swift](Sources/AIUsageBar/CodexUsageService.swift): local Codex usage.
- [CodexLiveUsageProvider.swift](Sources/AIUsageBar/CodexLiveUsageProvider.swift), [ClaudeUsageService.swift](Sources/AIUsageBar/ClaudeUsageService.swift), and [DeepSeekUsageService.swift](Sources/AIUsageBar/DeepSeekUsageService.swift): provider integrations.
