# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Deploy

```sh
# Tests and release packaging without private signing material
swift test
./scripts/build-app.sh --unsigned

# Local release packaging, fixed signing and verification
./scripts/build-app.sh --signed
```

Output: `.build/unsigned/AI Usage Bar.app` or, in signed mode, `.build/AI Usage Bar.app`. The script packages the SPM executable, Info.plist and icons explicitly. Quit the installed app before replacing `/Applications/AI Usage Bar.app` with a signed bundle. Preserve local settings and credentials.

Signed builds require the pinned **Tsukellow Local Code Signing** identity. Read the README for its local storage and recovery rules. Never substitute ad-hoc signing or create a new certificate during a signed build.

Requires Xcode with Swift 6. Run the packaged application, not `swift run`, so login-item integration and `LSUIElement` use the bundle identity.

## Architecture

macOS menu bar app (SwiftUI + AppKit). Five independently managed AI service models expose observable state. A shared `UsageRefreshScheduler` drives periodic refresh.

### Core flow

```
AppDelegate (NSApplicationDelegate)
  ├── codexModel: AppModel      ──→ CodexUsageService (actor)  ──→ chatgpt.com OAuth API
  ├── claudeModel: ClaudeModel  ──→ ClaudeUsageService (actor) ──→ claude.ai cookie API
  ├── deepSeekModel: DeepSeekModel ──→ DeepSeekUsageService (actor) ──→ platform.deepseek.com
  ├── antigravityModel: AntigravityModel ──→ local quota snapshot ←── Antigravity CLI statusLine callback
  └── grokModel: GrokModel ──→ official Grok Build CLI (ACP billing)
```

`AppDelegate` owns the `NSStatusBar` item, the `NSPopover` (hosting `CombinedMenuContentView`), and the Settings `NSWindow`. It redraws the menu bar icon from model state and display preferences.

### Model pattern

Each model follows the same enablement pattern:
1. Read `isEnabled` from `AppSettings` (UserDefaults; defaults on for Claude, Codex and DeepSeek, off for Antigravity and Grok)
2. If enabled, call `startLoop()` which delegates to `UsageRefreshScheduler.startRefreshLoop`
3. The loop: initial delay (configurable 10s–2m) → first refresh → periodic refresh (1/5/15 min)
4. `@Published var isEnabled` `didSet` writes to AppSettings and starts/stops the loop accordingly
5. Turning tracking off cancels the loop and in-flight work, and invalidates results from the old connection. Any provider can be turned off, including the last one. Antigravity instead checks its local snapshot every five seconds; its callback skips capture while disabled.

### refresh() flow (all models)

```
refresh()
  ├─ guard !isRefreshing (skip concurrent)
  ├─ guard token/cookie/auth present (otherwise set error + return)
  ├─ isRefreshing = true
  ├─ await service.fetchSnapshot()
  ├─ snapshot = result, errorMessage = nil
  └─ isRefreshing = false
```

Claude and Codex additionally call `scheduleResetRefresh(from: snapshot)` on success, which schedules a one-shot refresh at the earliest rate-limit window reset time + 3s (via `UsageRefreshScheduler.scheduleResetRefresh`). DeepSeek has no rate-limit windows, so it skips this.

### Settings storage

`AppSettings` is a namespace `enum` backed by `UserDefaults.standard`. All keys are in `AppSettings.swift`. SettingsView uses `@AppStorage` bindings for reactive UI. Per-model enable state is persisted in UserDefaults with the `isEnabled` `didSet` on each model.

### Menu bar icon

`MenuBarIconView` renders `[ServiceIconData]` as an `NSImage` using `NSBezierPath`. The menu bar includes a meter only for an enabled provider with menu bar display selected. The drop-down includes all enabled providers and uses the same snapshots. When no meters are visible, the app renders a neutral icon on the same button so its drop-down and Settings stay reachable.

### Network

`NetworkSession.shared` is the app's URLSession for direct provider requests. Antigravity login and quota requests stay in the official CLI; its callback shares only local quota snapshots. Grok's login and upstream billing request also stay in the official CLI.

## Git conventions

- Always use `git commit -s` (--signoff), never `Co-Authored-By`
