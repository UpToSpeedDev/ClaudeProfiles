# Claude Profiles

A tiny macOS launcher that lets you sign in to several Claude desktop
accounts at once.

## How it works

The official Claude app
([`/Applications/Claude.app`](https://claude.ai/download), bundle id
`com.anthropic.claudefordesktop`) is an Electron app that stores
cookies, localStorage, and preferences in
`~/Library/Application Support/Claude/`. A single shared directory
means a single account.

Claude Profiles launches the **same** unmodified Claude binary with
Chromium's `--user-data-dir=<path>` flag, pointing each profile at its
own folder under
`~/Library/Application Support/ClaudeProfiles/data/<uuid>/`. Each
profile keeps its own session, MCP/extension state, and chat history;
launching two profiles brings up two real Claude processes side by
side.

Nothing in `/Applications/Claude.app` is modified, cloned, or
re-signed, so notarization, auto-updates, and Anthropic's signature
are preserved.

## Build

Requires Xcode 16+ (uses `PBXFileSystemSynchronizedRootGroup`).
Deployment target is macOS 15 (Sequoia).

```sh
cd ClaudeProfiles
xcodebuild -project ClaudeProfiles.xcodeproj -scheme ClaudeProfiles -configuration Release build
open build/Release/ClaudeProfiles.app   # adjust to -derivedDataPath if you set one
```

Or open `ClaudeProfiles.xcodeproj` in Xcode and ⌘R.

## Caveats

- All running Claude instances share one Dock icon (same bundle id).
  Use the Claude Profiles window or its menu-bar item to switch
  between profiles.
- If a future Claude release stores its auth token in the macOS
  Keychain instead of in cookies/localStorage, profile isolation
  would have to be revisited.
- This launcher is not affiliated with Anthropic.
