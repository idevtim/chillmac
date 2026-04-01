# Contributing to ChillMac

Thanks for wanting to help keep Macs chilly! Here's how to get started.

## Setup

```bash
git clone https://github.com/YOUR_USERNAME/chillmac.git
cd chillmac
brew install xcodegen
xcodegen generate
```

Open `ChillMac.xcodeproj` in Xcode or build from the command line:

```bash
xcodebuild -project ChillMac.xcodeproj -scheme ChillMac build
```

Debug builds skip the helper's code signature check, so you don't need a Developer ID certificate to run the app locally.

## Making Changes

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Make sure it builds: `xcodegen generate && xcodebuild -scheme ChillMac build`
4. Test manually — there's no automated test suite
5. Open a PR

## Project Overview

- **`project.yml`** — XcodeGen config. The `.xcodeproj` is generated from this, don't edit the project file directly.
- **`ChillMac/`** — Main app (menu bar UI, SMC reads, SwiftUI views)
- **`FanControlHelper/`** — Privileged helper daemon (runs as root, handles SMC writes via XPC)
- **`Shared/`** — XPC protocol shared between the app and helper

## Guidelines

- Keep PRs focused — one feature or fix per PR
- Match the existing code style (no linter configured, just stay consistent)
- SwiftUI views go in `ChillMac/Views/`
- New monitors/data models go in `ChillMac/Fan/`
- The app has zero external dependencies — let's keep it that way unless there's a strong reason

## Architecture Notes

The app reads SMC data directly via IOKit. All write operations (fan speed, fan mode) go through XPC to the privileged helper. If you're adding a new SMC write operation, it needs to go through the helper — see `HelperProtocol.swift` for the XPC interface.

The helper validates the caller's code signature before accepting connections. In debug builds this check is skipped (`#if DEBUG`).

## Questions?

Open an issue — happy to help!
