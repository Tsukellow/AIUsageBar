# AIUsageBar

Tiny macOS menu bar scaffold for personal Codex usage tracking.

## What is implemented

- SwiftUI menu bar app shell
- Launch-at-login toggle via `SMAppService`
- Local usage summary from `~/.codex/state_5.sqlite`
- Auth identity parsing from `~/.codex/auth.json`
- Live Codex usage via the OAuth-backed `chatgpt.com` usage endpoint
- Hourly, daily, today, weekly, and lifetime aggregates
- Recent thread list

## What is intentionally left as the next step

- Codex CLI RPC fallback for live limits if the OAuth path fails
- Packaging/signing into a polished `.app`

The code already uses `CodexLiveUsageProviding`, and you can still plug in:

1. a Codex CLI RPC client using `account/rateLimits/read`, or
2. additional web/dashboard enrichment if you want more than rate-limit data

## Project layout

- `Sources/AIUsageBar/AIUsageBarApp.swift`: app entry point
- `Sources/AIUsageBar/AppModel.swift`: refresh loop and state
- `Sources/AIUsageBar/CodexUsageService.swift`: local Codex data loading
- `Sources/AIUsageBar/CodexLiveUsageProvider.swift`: hook for web/RPC usage fetches
- `Sources/AIUsageBar/MenuContentView.swift`: menu bar UI
- `Sources/AIUsageBar/SettingsView.swift`: basic settings

## Run

Open `Package.swift` in Xcode on a Mac with full Xcode installed, then run the `AIUsageBar` executable target.

From the terminal, you can still validate the package structure with:

```bash
swift build
```

If `xcodebuild` points only to Command Line Tools, switch to full Xcode first:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Next integration points

`CodexUsageService.fetchSnapshot(preferLiveUsage:)` already tries the live OAuth provider first and then keeps rendering the local summaries if the network call fails.
