# ChillMac

macOS menu bar app for system monitoring and fan control. Stay cool, stay fast.

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

## Build System

Uses **XcodeGen** (`project.yml`) to generate `ChillMac.xcodeproj`.

```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# Build from command line
xcodebuild -project ChillMac.xcodeproj -scheme ChillMac build
```

### Targets

| Target | Type | Bundle ID |
|--------|------|-----------|
| ChillMac | macOS app | com.timothymurphy.ChillMac |
| com.timothymurphy.ChillMac.Helper | command-line tool (daemon) | com.timothymurphy.ChillMac.Helper |

- Deployment target: macOS 13.0+
- Swift 5.9
- Hardened runtime enabled, sandbox disabled (required for IOKit access)
- Post-compile script copies helper into `Library/LaunchServices/`

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
FanControlHelper/
  main.swift        - Helper daemon entry point
  HelperDelegate.swift - XPC listener + code signature validation
  HelperService.swift  - Privileged fan control operations
Shared/
  HelperProtocol.swift - XPC protocol shared between app and helper
```

## Key Patterns

- **FanMonitor** is an `ObservableObject` that polls SMC every 2 seconds
- **StatusBarController** shows fan RPM in menu bar, manages NSPopover + detail panels
- **DetailPanelController** manages floating NSPanels adjacent to the main popover
- **SMCConnection** wraps IOKit calls; uses fixed-point encoding (fpe2 for RPM, sp78 for temperature)
- **HelperDelegate** validates caller code signature before accepting XPC connections
- Apple Silicon uses `Ftst` (test mode) key to bypass thermalmonitord; signal handlers ensure cleanup on exit
- `#if DEBUG` allows unsigned helper connections during development
- Fans always reset to auto mode on app launch
- Detail panels (CPU, Memory, Battery, Disk) open as floating NSPanels to the left of the main popover

## UI Design

- Dark blue-green gradient background
- Card-based layout with semi-transparent rounded rectangles
- Clickable info cards with hover effects and chevron indicators
- 420x640 main popover, 370x560 detail panels
- Footer with quit button, app name, and °F/°C toggle

## No Tests

There is no test suite. Testing is done manually via the UI.
