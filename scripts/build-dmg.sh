#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load credentials from .env
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  source "$PROJECT_DIR/.env"
  set +a
else
  echo "❌ .env file not found at $PROJECT_DIR/.env"
  exit 1
fi

# ─── Pre-flight: release notes check ────────────────────────────────────────
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PROJECT_DIR/ChillMac/Info.plist")
RELEASE_NOTES="$PROJECT_DIR/release-notes/v$VERSION.md"
if [ ! -f "$RELEASE_NOTES" ]; then
  echo "❌ Missing release notes: release-notes/v$VERSION.md"
  echo "   Create this file before releasing."
  exit 1
fi
echo "✓ Found release notes for v$VERSION"

# Sparkle decides whether an update is newer by comparing CFBundleVersion, not the
# marketing string. If it doesn't increase, every existing install silently concludes it
# is already up to date — a failure with no error anywhere. Checked rather than
# auto-synced because PlistBuddy rewrites the file and strips its comments.
BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PROJECT_DIR/ChillMac/Info.plist")
if [ "$BUNDLE_VERSION" != "$VERSION" ]; then
  echo "❌ CFBundleVersion ($BUNDLE_VERSION) != CFBundleShortVersionString ($VERSION)"
  echo "   Sparkle compares CFBundleVersion — users would never be offered this update."
  echo "   Fix: set CFBundleVersion to $VERSION in ChillMac/Info.plist"
  exit 1
fi
echo "✓ Version keys agree (v$VERSION)"

APP_NAME="ChillMac"
GITHUB_REPO="idevtim/chillmac"
HELPER_BUNDLE_ID="com.idevtim.ChillMac.Helper"
SIGNING_IDENTITY="Developer ID Application: Tim Murphy ($APPLE_TEAM_ID)"
TEAM_ID="$APPLE_TEAM_ID"

BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DIR="$BUILD_DIR/DerivedData"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
# Sparkle downloads a zip, not the dmg. Kept in its own directory because
# generate_appcast treats that directory as the archive set it maintains.
UPDATES_DIR="$BUILD_DIR/updates"
ZIP_PATH="$UPDATES_DIR/$APP_NAME-$VERSION.zip"
APPCAST_PATH="$PROJECT_DIR/appcast.xml"

# ─── Clean ───────────────────────────────────────────────────────────────────
echo "🧹 Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ─── Build ───────────────────────────────────────────────────────────────────
echo "🔨 Building $APP_NAME..."
xcodebuild \
  -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGN_STYLE="Manual" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  DSTROOT="$BUILD_DIR/dst" \
  2>&1 | tail -5

# Find the built .app
BUILT_APP=$(find "$DERIVED_DIR" -name "$APP_NAME.app" -type d | head -1)
if [ -z "$BUILT_APP" ]; then
  echo "❌ Build failed — .app not found"
  exit 1
fi
cp -R "$BUILT_APP" "$APP_PATH"
echo "   ✓ Built: $APP_PATH"

# ─── Deep sign (inside-out) ─────────────────────────────────────────────────
echo "🔏 Deep code signing (inside-out)..."

# 1. Sign the helper first (innermost)
HELPER_PATH="$APP_PATH/Contents/Library/LaunchServices/$HELPER_BUNDLE_ID"
if [ -f "$HELPER_PATH" ]; then
  codesign --force --timestamp --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$PROJECT_DIR/FanControlHelper/Helper.entitlements" \
    "$HELPER_PATH"
  echo "   ✓ Helper signed"
fi

# 2. Sparkle ships executables nested inside its framework — two XPC services, an updater
#    app and the Autoupdate tool. Signing only the .framework leaves those with the
#    original signature and notarization rejects the build. They must be signed
#    individually, innermost first.
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
  for nested in \
    "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc" \
    "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc" \
    "$SPARKLE_FW/Versions/B/Updater.app" \
    "$SPARKLE_FW/Versions/B/Autoupdate"; do
    if [ -e "$nested" ]; then
      codesign --force --timestamp --options runtime \
        --sign "$SIGNING_IDENTITY" \
        "$nested"
      echo "   ✓ Signed: Sparkle/$(basename "$nested")"
    fi
  done
fi

# 3. Sign any frameworks/dylibs (framework bundles come after their nested contents)
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
  find "$APP_PATH/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) | while read -r lib; do
    codesign --force --timestamp --options runtime \
      --sign "$SIGNING_IDENTITY" \
      "$lib"
    echo "   ✓ Signed: $(basename "$lib")"
  done
fi

# 4. Sign the main app (outermost)
codesign --force --timestamp --options runtime \
  --sign "$SIGNING_IDENTITY" \
  --entitlements "$PROJECT_DIR/ChillMac/ChillMac.entitlements" \
  "$APP_PATH"
echo "   ✓ App signed"

# ─── Verify ─────────────────────────────────────────────────────────────────
echo "🔍 Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1

# ─── Notarize the app itself ────────────────────────────────────────────────
# Done before the DMG so the ticket can be stapled onto the .app. Sparkle installs the
# app straight out of the zip, and an unstapled bundle has to reach Apple to validate —
# which fails for anyone updating while offline.
echo "📤 Notarizing app bundle..."
mkdir -p "$UPDATES_DIR"
NOTARIZE_ZIP="$BUILD_DIR/notarize-app.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait
rm -f "$NOTARIZE_ZIP"

echo "📎 Stapling ticket to app..."
xcrun stapler staple "$APP_PATH"

# ─── Create the Sparkle update archive ──────────────────────────────────────
# Zipped from the stapled bundle, so what users download is self-validating.
echo "📦 Creating update archive..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "   ✓ $ZIP_PATH"

# ─── Create DMG ──────────────────────────────────────────────────────────────
echo "💿 Creating DMG..."
rm -f "$DMG_PATH"
create-dmg \
  --volname "$APP_NAME" \
  --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 150 190 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 450 190 \
  "$DMG_PATH" \
  "$APP_PATH" \
  2>&1 || {
    echo "   ⚠ Retrying without volicon..."
    rm -f "$DMG_PATH"
    create-dmg \
      --volname "$APP_NAME" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 100 \
      --icon "$APP_NAME.app" 150 190 \
      --hide-extension "$APP_NAME.app" \
      --app-drop-link 450 190 \
      "$DMG_PATH" \
      "$APP_PATH"
  }

# ─── Sign the DMG ───────────────────────────────────────────────────────────
echo "🔏 Signing DMG..."
codesign --force --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$DMG_PATH"

# ─── Notarize ───────────────────────────────────────────────────────────────
echo "📤 Submitting to Apple notary service..."
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# ─── Final verification ─────────────────────────────────────────────────────
echo "🔍 Final Gatekeeper check..."
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH" 2>&1

echo ""
echo "✅ Build complete: $DMG_PATH (v$VERSION)"

# ─── Generate the Sparkle appcast ───────────────────────────────────────────
echo "📰 Generating appcast..."

GENERATE_APPCAST=$(find "$DERIVED_DIR/SourcePackages/artifacts" -name generate_appcast -type f 2>/dev/null | head -1)
if [ -z "$GENERATE_APPCAST" ]; then
  echo "❌ generate_appcast not found — is the Sparkle package resolved?"
  exit 1
fi

# A .md file sharing the archive's basename becomes that release's notes in the update
# dialog, so users see the same text as on GitHub.
cp "$RELEASE_NOTES" "$UPDATES_DIR/$APP_NAME-$VERSION.md"

# Seed with the committed appcast so previously published entries survive; without it
# the feed is regenerated from just this one archive and loses its history.
if [ -f "$APPCAST_PATH" ]; then
  cp "$APPCAST_PATH" "$UPDATES_DIR/appcast.xml"
fi

# Signs each archive with the EdDSA key from the login keychain. The download prefix has
# to match where the assets actually land, which is this tag's release page.
# --embed-release-notes puts the notes in the feed itself. Without it Sparkle derives a
# link from SUFeedURL and expects the .md beside the appcast in the repo root, which 404s.
"$GENERATE_APPCAST" \
  --embed-release-notes \
  --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/v$VERSION/" \
  --link "https://github.com/$GITHUB_REPO" \
  --full-release-notes-url "https://github.com/$GITHUB_REPO/releases" \
  -o "$UPDATES_DIR/appcast.xml" \
  "$UPDATES_DIR"

cp "$UPDATES_DIR/appcast.xml" "$APPCAST_PATH"
echo "   ✓ appcast.xml updated"

# ─── GitHub Release ─────────────────────────────────────────────────────────
echo "🚀 Creating GitHub release v$VERSION..."
git tag "v$VERSION" 2>/dev/null || echo "   Tag v$VERSION already exists"
git push origin "v$VERSION" 2>&1

gh release create "v$VERSION" "$DMG_PATH" "$ZIP_PATH" --title "v$VERSION" --notes-file "$RELEASE_NOTES"
echo "✅ Released v$VERSION on GitHub"

# ─── Publish the appcast ────────────────────────────────────────────────────
# Last, and only once the assets exist: the feed is served from main, so committing it
# earlier would point live clients at a download URL that 404s.
echo "📡 Publishing appcast to main..."
git add "$APPCAST_PATH"
if git diff --cached --quiet -- "$APPCAST_PATH"; then
  echo "   appcast.xml unchanged"
else
  git commit -m "chore: publish appcast for v$VERSION" -- "$APPCAST_PATH"
  git push origin HEAD
  echo "   ✓ appcast.xml published — clients will see v$VERSION within their next check"
fi
