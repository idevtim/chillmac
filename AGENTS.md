# Fan Sooner

macOS menu bar app for system monitoring and fan control. Stay cool, stay fast.

> Product name: **Fan Sooner**. Code module / Xcode target / bundle IDs remain `ChillMac` / `com.idevtim.ChillMac` so the privileged helper and Login Items keep working.

## Architecture

Two-process architecture with privilege separation:

- **Main App** (unprivileged) — Menu bar UI, read-only SMC monitoring, SwiftUI popover with detail panels
- **Privileged Helper** (root) — Write operations to SMC (fan speed, fan mode) via XPC

The app reads SMC data directly via IOKit. Write operations go through XPC to the helper daemon which runs as root.

```
Main App (UI + read-only SMC) --XPC--> Helper Daemon (root, write SMC)
                                            |
                                      IOKit / AppleSMC
```

## Features

- **Fan Control** — Live RPM in menu bar, per-fan manual speed sliders, auto/manual toggle
- **CPU Monitor** — Real-time usage %, historical graph, top consuming apps, temperature
- **Memory Monitor** — Active/wired/compressed breakdown donut chart, pressure %, swap, top consumers
- **Battery Monitor** — Charge gauge, health %, cycle count, temperature, charging status
- **Disk Monitor** — Category breakdown (Apps/Downloads/Documents/Desktop/Other), SSD temperature
- **Temperature Sensors** — Color-coded display of all detected SMC sensors (CPU, GPU, DRAM, SSD, etc.)
- **System Info** — Machine model, chip name, RAM, macOS version

## Getting started (how to run)

Two different “start” paths. Pick the right one:

### A. Day-to-day UI / monitoring (Xcode Debug)

Fine for menu bar UI, sensors, and Native Cool. Adhoc-signed Debug builds **do not** give a reliable root helper for Max/Ultra.

```bash
brew install xcodegen   # once
xcodegen generate
open ChillMac.xcodeproj # Run (⌘R) — or:
xcodebuild -project ChillMac.xcodeproj -scheme ChillMac -configuration Debug build
```

### B. Fan control that actually works (Release + notarized in `/Applications`)

Max/Ultra need the `SMAppService` LaunchDaemon. Apple requires the **parent app** to be Developer ID–signed and **notarized**. Copying a Debug `.app` into `/Applications` will look installed but the helper dies with `EX_CONFIG` / launch-constraint errors.

```bash
# 1. .env from .env.example — APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
#    Optional: APPLE_SIGNING_NAME="Noah Deskin" (default: Tim Murphy)
./scripts/build-dmg.sh

# Or: Release build + deep-sign helper then app, zip, notarytool submit --wait, stapler staple
# 2. Install only under /Applications (not Desktop / Downloads — TCC/MAC path traps)
# 3. Launch once → approve Fan Sooner under System Settings → General → Login Items
#    (Allow in the Background). Settings → Helper should show Ready.
```

**Quick health check after install:**

```bash
launchctl print system/com.idevtim.ChillMac.Helper3 | rg 'state =|pid =|job state|program identifier'
# Expect: state = running, a pid, program under Contents/Library/HelperTools/
```

**If the helper is stuck** (`spawn failed`, `EX_CONFIG`, Helper “Not ready”, or poisoned BTM after rebrand/re-sign):

1. Prefer in-app **Install Helper** (unregister → register).
2. Confirm Login Items still allows the background item.
3. Nuclear reset (wipes *all* third-party Login Items approvals): `sudo sfltool resetbtm` then reboot.
4. Do not leave old `ChillMac.app` / DerivedData copies around with the same bundle ID while testing installs.

### Helper layout (do not regress)

| | Correct (SMAppService) | Wrong (SMJobBless-era) |
|--|------------------------|-------------------------|
| Binary | `Contents/Library/HelperTools/com.idevtim.ChillMac.Helper` | `Contents/Library/LaunchServices/…` |
| Plist | `Contents/Library/LaunchDaemons/com.idevtim.ChillMac.Helper3.plist` | Old `Helper.plist` / LaunchServices path |
| Launchd label / Mach service | `com.idevtim.ChillMac.Helper3` | `com.idevtim.ChillMac.Helper` |
| Plist keys | `BundleProgram` + `RunAtLoad`; no `SMPrivilegedExecutables` / `SMAuthorizedClients` | Absolute `Program`, LaunchServices placement |

Apple DTS: LaunchServices is for **SMJobBless**, not SMAppService. Working peer pattern on macOS: HelperTools + `RunAtLoad` + explicit `app-sandbox = false` on the helper, notarized parent app.

## Build System

Uses **XcodeGen** (`project.yml`) to generate `ChillMac.xcodeproj`.

```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# Build from command line
xcodebuild -project ChillMac.xcodeproj -scheme ChillMac build

# Build signed DMG for distribution (requires .env with Apple credentials)
./scripts/build-dmg.sh
```

### Distribution (`scripts/build-dmg.sh`)

Full release pipeline that builds, signs, creates DMG, notarizes, and staples in one step.

Requires a `.env` file with `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID` (see `.env.example`). Optional `APPLE_SIGNING_NAME` overrides the Developer ID CN (default `Tim Murphy`). Also requires `create-dmg` (`brew install create-dmg`) and a Developer ID Application certificate.

Steps performed:
1. Clean build via `xcodebuild` (Release config)
2. Deep code sign inside-out (helper → frameworks → app) with hardened runtime
3. Create DMG with `create-dmg` (app icon, drag-to-Applications layout)
4. Sign the DMG
5. Notarize via `notarytool` and staple the ticket
6. Gatekeeper verification

Output: `build/Fan Sooner.dmg`

### Targets

| Target | Type | Bundle ID |
|--------|------|-----------|
| ChillMac | macOS app | com.idevtim.ChillMac |
| com.idevtim.ChillMac.Helper | command-line tool (daemon) | com.idevtim.ChillMac.Helper |

- Deployment target: macOS 13.0+
- Swift 5.9
- Hardened runtime enabled, sandbox disabled (required for IOKit access)
- Post-compile script copies helper into `Library/HelperTools/` and the launchd plist as `Helper3.plist`

## Project Structure

```
ChillMac/
  App/              - Entry point (main.swift), StatusBarController, DetailPanelController, AppSettings
  Views/            - SwiftUI views
    PopoverView       Main dashboard with system info cards, fans, temperatures
    FanRowView        Per-fan controls (RPM display, manual toggle, speed slider)
    TemperatureRowView  Individual temperature sensor display
    CpuDetailView     CPU detail panel (usage graph, uptime, temperature, top consumers)
    MemoryDetailView  Memory detail panel (donut chart, pressure, swap, top consumers)
    BatteryDetailView Battery detail panel (charge gauge, health, cycles, temperature)
    DiskDetailView    Disk detail panel (category donut chart, usage, SSD temperature)
  Fan/              - Data models and monitoring engines
    FanMonitor        ObservableObject polling SMC every 2s for fan + temperature data
    FanInfo           Fan data model (RPM, min/max, mode)
    TemperatureSensor Temperature sensor model
    SystemInfo        Hardware info, disk usage, uptime (polls every 30s)
    CpuInfo           CPU usage tracking with history (polls every 2s)
    MemoryInfo        Memory stats via host_statistics64 (polls every 3s)
    BatteryInfo       Battery info via IOKit/IOPowerSources (polls every 5s)
  SMC/              - IOKit bridge (SMCConnection, SMCTypes, SMCKeys)
  XPC/              - HelperConnection (client), HelperInstaller
  Preview/          - PreviewSupport factories for SwiftUI canvas + tests (#if DEBUG)
FanControlHelper/
  main.swift        - Helper daemon entry point
  HelperDelegate.swift - XPC listener + code signature validation
  HelperService.swift  - Privileged fan control operations
Shared/
  HelperProtocol.swift - XPC protocol shared between app and helper
scripts/
  build-dmg.sh      - Release pipeline: build, sign, DMG, notarize, staple
```

## Key Patterns

- **FanMonitor** is an `ObservableObject` that polls SMC every 2 seconds
- **StatusBarController** shows fan RPM in menu bar, manages NSPopover + detail panels
- **DetailPanelController** manages floating NSPanels adjacent to the main popover
- **SMCConnection** wraps IOKit calls; uses fixed-point encoding (fpe2 for RPM, sp78 for temperature)
- **HelperDelegate** validates caller code signature before accepting XPC connections
- Apple Silicon uses `Ftst` (test mode) key to bypass thermalmonitord; signal handlers ensure cleanup on exit
- `#if DEBUG` allows unsigned helper connections during development (UI/dev only — not a substitute for notarized `/Applications` installs)
- **HelperInstaller.reregister()** unregisters then registers when the daemon is stale or the binary moved; register-only loops leave BTM/`needs LWCR update` poison
- Fans always reset to auto mode on app launch
- Detail panels (CPU, Memory, Battery, Disk) open as floating NSPanels to the left of the main popover

## UI Design

- Dark blue-green gradient background
- Card-based layout with semi-transparent rounded rectangles
- Clickable info cards with hover effects and chevron indicators
- 420x640 main popover, 370x560 detail panels
- Footer with quit button, app name, and °F/°C toggle

## Testing

Unit tests live in `ChillMacTests` (Swift Testing). Run:

```bash
xcodegen generate && xcodebuild -project ChillMac.xcodeproj -scheme ChillMac -destination 'platform=macOS' test
```

Layout (door-open for future suites — prefer these homes over reshuffling):

```
ChillMacTests/
  Support/          Tags.swift, harness smoke
  Fixtures/         PreviewSupportTests, etc.
  Unit/             Pure / parallel-safe (Fan/, SMC/, App/)
  Integration/      Live host / XPC later (Fan/, SMC/, XPC/)
  Mocks/            Fakes for isolation
```

- Use `@Test` / `#expect` / `@Suite` (Swift Testing only — no XCTest UI suite yet)
- Tag suites via `Support/Tags.swift`: `.unit`, `.integration`, `.fan`, `.fixtures` — e.g. `@Suite("PerformanceCurve", .tags(.unit, .fan))`. Default parallel OK for pure math; use `.serialized` only for shared UserDefaults/SMC. Tags enable CI filters without changing `project.yml`
- Sample data for fixtures and canvas comes from `ChillMac/Preview/PreviewSupport.swift` — do not hit live SMC/XPC in unit tests or invent local sample data in views
- SwiftUI convention: add in-file `#Preview("…")` (plain macros, no traits) wired to `PreviewSupport` factories; keep `#Preview` under `#if DEBUG`
- Zero external test dependencies (no ViewInspector, no snapshot libs)
- Test plan: `TestPlans/Unit.xctestplan`
