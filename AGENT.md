# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Deploy

```bash
# Debug build
swift build

# Release build + package .app bundle + deploy to /Applications
swift build -c release && \
  cp .build/arm64-apple-macosx/release/AIUsageBar \
     ".build/arm64-apple-macosx/AI Usage Bar.app/Contents/MacOS/AIUsageBar" && \
  codesign --force --sign - ".build/arm64-apple-macosx/AI Usage Bar.app" && \
  rm -rf "/Applications/AI Usage Bar.app" && \
  cp -R ".build/arm64-apple-macosx/AI Usage Bar.app" "/Applications/AI Usage Bar.app"

# Kill running instance before deploying a new one
pkill -f AIUsageBar
```

Requires full Xcode (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`). SPM auto-creates the `.app` bundle because `Package.swift` embeds `Info.plist` into the binary via `-sectcreate __TEXT __info_plist`.

**Do not** use `swift run` — it runs as a plain binary without the `.app` bundle, which breaks `SMAppService` (launch-at-login) and `LSUIElement`.

## Architecture

macOS menu bar app (SwiftUI + AppKit). Three independently managed AI service models, each with its own `@ObservableObject` and `actor`-based API service. A shared `UsageRefreshScheduler` drives periodic refresh for all models.

### Core flow

```
AppDelegate (NSApplicationDelegate)
  ├── codexModel: AppModel      ──→ CodexUsageService (actor)  ──→ chatgpt.com OAuth API
  ├── claudeModel: ClaudeModel  ──→ ClaudeUsageService (actor) ──→ claude.ai cookie API
  └── deepSeekModel: DeepSeekModel ──→ DeepSeekUsageService (actor) ──→ platform.deepseek.com
```

`AppDelegate` owns the `NSStatusBar` item, the `NSPopover` (hosting `CombinedMenuContentView`), and the Settings `NSWindow`. It subscribes to `objectWillChange` on all three models to redraw the menu bar icon on any state change.

### Model pattern

Every model follows the same pattern in `init()`:
1. Read `isEnabled` from `AppSettings` (UserDefaults, default `true`)
2. If enabled, call `startLoop()` which delegates to `UsageRefreshScheduler.startRefreshLoop`
3. The loop: initial delay (configurable 10s–2m) → first refresh → periodic refresh (1/5/15 min)
4. `@Published var isEnabled` `didSet` writes to AppSettings and starts/stops the loop accordingly
5. Each model prevents itself from being disabled if it's the last enabled model (checks other models' AppSettings keys)

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

`MenuBarIconView` renders `[ServiceIconData]` as an `NSImage` using `NSBezierPath`. Each `ServiceIconData` gets a ring arc (0–1 fraction), two text lines, and an optional ring color. `AppDelegate.updateStatusItemImage()` conditionally includes only enabled models. When all are disabled, the icon is set to `nil` (invisible).

### Network

`NetworkSession.shared` is a `URLSession` with a `TrustDelegate` that uses `SecTrustEvaluateWithError` to handle TLS for ad-hoc signed builds. All services use it.

## Git conventions

- Always use `git commit -s` (--signoff), never `Co-Authored-By`
