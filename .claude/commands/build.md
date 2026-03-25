---
description: Build ChillMac (regenerate Xcode project and compile)
---
## Build ChillMac

!`xcodegen generate`

!`xcodebuild -project ChillMac.xcodeproj -scheme ChillMac -configuration Debug build 2>&1 | tail -20`

Report whether the build succeeded or failed. If it failed, analyze the errors and suggest fixes.
