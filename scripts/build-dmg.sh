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

APP_NAME="ChillMac"
HELPER_BUNDLE_ID="com.idevtim.ChillMac.Helper"
SIGNING_IDENTITY="Developer ID Application: Tim Murphy ($APPLE_TEAM_ID)"
TEAM_ID="$APPLE_TEAM_ID"

BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DIR="$BUILD_DIR/DerivedData"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

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

# 2. Sign any frameworks/dylibs
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
  find "$APP_PATH/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) | while read -r lib; do
    codesign --force --timestamp --options runtime \
      --sign "$SIGNING_IDENTITY" \
      "$lib"
    echo "   ✓ Signed: $(basename "$lib")"
  done
fi

# 3. Sign the main app (outermost)
codesign --force --timestamp --options runtime \
  --sign "$SIGNING_IDENTITY" \
  --entitlements "$PROJECT_DIR/ChillMac/ChillMac.entitlements" \
  "$APP_PATH"
echo "   ✓ App signed"

# ─── Verify ─────────────────────────────────────────────────────────────────
echo "🔍 Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1

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

VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
echo ""
echo "✅ Build complete: $DMG_PATH (v$VERSION)"

# ─── GitHub Release ─────────────────────────────────────────────────────────
echo "🚀 Creating GitHub release v$VERSION..."
git tag "v$VERSION" 2>/dev/null || echo "   Tag v$VERSION already exists"
git push origin "v$VERSION" 2>&1

gh release create "v$VERSION" "$DMG_PATH" --title "v$VERSION" --notes-file "$RELEASE_NOTES"
echo "✅ Released v$VERSION on GitHub"
