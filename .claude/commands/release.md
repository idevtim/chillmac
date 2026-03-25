---
description: Build a signed DMG for distribution
---
## Build Release DMG

Run the full release pipeline (build, sign, DMG, notarize, staple):

!`./scripts/build-dmg.sh 2>&1 | tail -40`

Report whether the release build succeeded. If notarization failed, show the relevant error.
