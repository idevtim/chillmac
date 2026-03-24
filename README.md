# MacFanControl

A lightweight macOS menu bar app for monitoring temperatures and controlling fan speeds. Reads sensor data directly from the System Management Controller (SMC) via IOKit and provides manual fan speed override through a privileged helper daemon.

## Features

- Live fan RPM display in the menu bar
- Temperature readings for CPU, GPU, memory, battery, and more
- Manual fan speed control with per-fan sliders
- Toggle between automatic and manual fan modes
- Color-coded temperature indicators (green → yellow → orange → red)
- Apple Silicon and Intel Mac support

## Requirements

- macOS 13.0+
- Xcode 15+ (to build)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (to generate the Xcode project)

## Building

```bash
# Generate the Xcode project
xcodegen generate

# Build
xcodebuild -project MacFanControl.xcodeproj -scheme MacFanControl build
```

Or open `MacFanControl.xcodeproj` in Xcode and build from there.

## How It Works

The app uses a two-process architecture with privilege separation:

- **Main app** (unprivileged) — Runs as a menu bar item, reads SMC sensors every 2 seconds, and displays a SwiftUI popover with temperature and fan data.
- **Helper daemon** (root) — A privileged helper tool installed via `SMAppService` that handles write operations to the SMC (setting fan speeds and modes) over XPC.

On first launch, the app prompts for administrator credentials to install the helper daemon. The helper validates the caller's code signature before accepting any XPC connections.

On Apple Silicon Macs, the helper also manages SMC test mode to bypass `thermalmonitord` when manually controlling fans. Signal handlers ensure test mode is disabled if the helper exits unexpectedly.

## Project Structure

```
MacFanControl/
  App/              Entry point and status bar controller
  Views/            SwiftUI views (popover, fan rows, temperature rows)
  Fan/              Data models and polling engine
  SMC/              IOKit bridge to Apple SMC driver
  XPC/              Helper connection and installation
FanControlHelper/   Privileged helper daemon
Shared/             XPC protocol shared between app and helper
```
