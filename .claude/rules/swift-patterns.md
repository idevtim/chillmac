---
paths:
  - "ChillMac/**/*.swift"
  - "FanControlHelper/**/*.swift"
  - "Shared/**/*.swift"
---
# Swift Patterns

- Use ObservableObject + @Published for reactive state; avoid Combine unless already used in the file
- SMC reads happen on the main app; writes go through XPC to the privileged helper
- Use MainActor for all UI-related code; background work via Task.detached or DispatchQueue
- Fixed-point encoding: fpe2 for fan RPM, sp78 for temperatures — do not change these encodings
- Helper code signature validation in HelperDelegate must not be weakened outside #if DEBUG
- Prefer guard-let over if-let for early returns
- Keep SwiftUI views small — extract reusable components into their own files in Views/
