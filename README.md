# ActiveLeft

ActiveLeft is a tiny macOS menu bar app for switching between two display states:

- `Active`: keep the display awake with `/usr/bin/caffeinate -d -w <app-pid>`.
- `Left`: stop ActiveLeft's own `caffeinate` process and return to the existing macOS display sleep settings.

It is intentionally display-only. ActiveLeft does not edit `pmset`, does not require `sudo`, does not talk to the network, and does not try to manage system sleep or closed-lid behavior.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools

## Build

```bash
swift build
```

To create a `.app` bundle:

```bash
./scripts/build_app.sh
```

The app bundle is written to:

```text
build/ActiveLeft.app
```

`build_app.sh` tries SwiftPM first. If the local Command Line Tools install has a SwiftPM/SDK mismatch, it falls back to a matching Objective-C AppKit build with the same app behavior.

## Run

```bash
open build/ActiveLeft.app
```

The menu bar item starts as `ActiveLeft: Left`.

- Left-click the menu bar item to toggle between `Active` and `Left`.
- Right-click it to open a menu with `Switch to Active/Left` and `Quit ActiveLeft`.

## Start at Login

```bash
./scripts/install_launch_agent.sh
```

This installs:

```text
~/Library/LaunchAgents/com.hozumitaito.activeleft.plist
```

No `sudo` is used.

To remove it:

```bash
./scripts/uninstall_launch_agent.sh
```

## Configuration

The default bundle identifier and LaunchAgent label are `com.hozumitaito.activeleft`.

You can override the app bundle identifier during build:

```bash
ACTIVELEFT_BUNDLE_ID=io.github.example.activeleft ./scripts/build_app.sh
```

You can override the LaunchAgent label during install or uninstall:

```bash
ACTIVELEFT_LAUNCH_AGENT_LABEL=io.github.example.activeleft ./scripts/install_launch_agent.sh
ACTIVELEFT_LAUNCH_AGENT_LABEL=io.github.example.activeleft ./scripts/uninstall_launch_agent.sh
```

## Verification

Before and after toggling, `pmset` settings should stay the same:

```bash
pmset -g custom
```

When `Active` is enabled, this should show a display sleep assertion owned by `caffeinate`:

```bash
pmset -g assertions
```

You can run the bundled smoke test:

```bash
./scripts/self_test.sh
```

## What ActiveLeft Is Not

ActiveLeft is not a full power-management suite. It does not schedule wake/sleep windows, prevent all sleep modes, keep a closed MacBook awake, or replace tools such as Amphetamine. It is a small display-only toggle for people who want one obvious menu bar state and no persistent system-setting changes.

## License

MIT
