# MacFanControl

macOS menu bar app for monitoring and controlling fan speeds via the System Management Controller (SMC).

## Architecture

Two-process architecture with privilege separation:

- **Main App** (unprivileged) — Menu bar UI, read-only SMC monitoring, SwiftUI popover
- **Privileged Helper** (root) — Write operations to SMC (fan speed, fan mode) via XPC

The app reads SMC data directly via IOKit. Write operations go through XPC to the helper daemon which runs as root.

```
Main App (UI + read-only SMC) --XPC--> Helper Daemon (root, write SMC)
                                            |
                                      IOKit / AppleSMC
```

## Build System

Uses **XcodeGen** (`project.yml`) to generate `MacFanControl.xcodeproj`.

```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# Build from command line
xcodebuild -project MacFanControl.xcodeproj -scheme MacFanControl build
```

### Targets

| Target | Type | Bundle ID |
|--------|------|-----------|
| MacFanControl | macOS app | com.timothymurphy.MacFanControl |
| com.timothymurphy.MacFanControl.Helper | command-line tool (daemon) | com.timothymurphy.MacFanControl.Helper |

- Deployment target: macOS 13.0+
- Swift 5.9
- Hardened runtime enabled, sandbox disabled (required for IOKit access)
- Post-compile script copies helper into `Library/LaunchServices/`

## Project Structure

```
MacFanControl/
  App/              - Entry point (main.swift), StatusBarController
  Views/            - SwiftUI views (PopoverView, FanRowView, TemperatureRowView)
  Fan/              - Data models (FanInfo, TemperatureSensor) and FanMonitor polling engine
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
- **StatusBarController** shows fan RPM in menu bar, manages NSPopover
- **SMCConnection** wraps IOKit calls; uses fixed-point encoding (fpe2 for RPM, sp78 for temperature)
- **HelperDelegate** validates caller code signature before accepting XPC connections
- Apple Silicon uses `Ftst` (test mode) key to bypass thermalmonitord; signal handlers ensure cleanup on exit
- `#if DEBUG` allows unsigned helper connections during development

## No Tests

There is no test suite. Testing is done manually via the UI.
