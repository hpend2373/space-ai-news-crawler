#!/bin/bash
set -e

APP_PATH="/Users/minyeop/Library/Developer/Xcode/DerivedData/ai_app-chdpijxqakbldscwvdeulahhaabb/Build/Products/Debug/Daily.app"
DMG_NAME="Daily"
DMG_OUTPUT="/Users/minyeop/ai app/Daily.dmg"
STAGING="/tmp/dmg_staging"

echo "=== Creating DMG for Daily.app ==="

# Clean up any previous staging
rm -rf "$STAGING"
mkdir -p "$STAGING"

# Copy app to staging
echo "Copying app..."
cp -R "$APP_PATH" "$STAGING/"

# Create symlink to Applications folder
ln -s /Applications "$STAGING/Applications"

# Create the DMG
echo "Creating DMG..."
rm -f "$DMG_OUTPUT"

# Create a temporary DMG
hdiutil create \
    -volname "$DMG_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_OUTPUT"

# Clean up
rm -rf "$STAGING"

echo ""
echo "=== Done! ==="
echo "DMG saved to: $DMG_OUTPUT"
ls -lh "$DMG_OUTPUT"
