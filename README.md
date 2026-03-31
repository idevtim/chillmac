# ChillMac

A macOS menu bar app for monitoring your system and controlling fan speeds. Stay cool, stay fast.

## Features

- **Fan Control** — Live RPM display in the menu bar with per-fan manual speed sliders
- **CPU Monitor** — Real-time usage graph, top consuming apps, temperature, and uptime
- **Memory Monitor** — Usage breakdown with donut chart, pressure, swap, and top consumers
- **Battery Monitor** — Charge gauge, health percentage, cycle count, and temperature
- **Disk Monitor** — Storage breakdown by category with SSD temperature
- **Temperature Sensors** — Color-coded readings for CPU, GPU, memory, SSD, battery, and more
- **System Info** — Machine model, chip, RAM, macOS version at a glance
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
xcodebuild -project ChillMac.xcodeproj -scheme ChillMac build
```

Or open `ChillMac.xcodeproj` in Xcode and build from there.

### Building a signed DMG for distribution

The `scripts/build-dmg.sh` script handles the full release pipeline: build, code sign (inside-out), create DMG, notarize with Apple, and staple the ticket.

**Prerequisites:**
- A **Developer ID Application** certificate installed in Keychain
- [create-dmg](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`)
- A `.env` file in the project root (see `.env.example`):
  - `APPLE_ID` — Your Apple ID email
  - `APPLE_APP_SPECIFIC_PASSWORD` — App-specific password from appleid.apple.com
  - `APPLE_TEAM_ID` — Your 10-character team ID

```bash
./scripts/build-dmg.sh
```

The signed and notarized DMG will be at `build/ChillMac.dmg`.

## How It Works

The app uses a two-process architecture with privilege separation:

- **Main app** (unprivileged) — Runs as a menu bar item, reads SMC sensors every 2 seconds, and displays a SwiftUI popover with system monitoring dashboards.
- **Helper daemon** (root) — A privileged helper tool installed via `SMAppService` that handles write operations to the SMC (setting fan speeds and modes) over XPC.

On first launch, the app prompts for administrator credentials to install the helper daemon. The helper validates the caller's code signature before accepting any XPC connections.

On Apple Silicon Macs, the helper also manages SMC test mode to bypass `thermalmonitord` when manually controlling fans. Signal handlers ensure test mode is disabled if the helper exits unexpectedly.

## Development Notes

The privileged helper validates the caller's code signature before accepting XPC connections. If you're building from source with your own signing identity, debug builds (`#if DEBUG`) skip this check so the helper works without matching the original signature.

Fans are always reset to automatic mode when the app launches.

## License

MIT — see [LICENSE](LICENSE) for details.

## Project Structure

```
ChillMac/
  App/              Entry point, status bar controller, detail panel controller
  Views/            SwiftUI views (dashboard, fan controls, detail panels)
  Fan/              Data models and monitoring engines (CPU, memory, battery, disk)
  SMC/              IOKit bridge to Apple SMC driver
  XPC/              Helper connection and installation
FanControlHelper/   Privileged helper daemon
Shared/             XPC protocol shared between app and helper
```
