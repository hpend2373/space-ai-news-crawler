#!/bin/bash
set -e

APP_PATH="${HOME}/Library/Developer/Xcode/DerivedData/ai_app-chdpijxqakbldscwvdeulahhaabb/Build/Products/Release/Daily.app"
DMG_NAME="Daily"
DMG_TEMP="/tmp/Daily_temp.dmg"
DMG_OUTPUT="${HOME}/ai app/Daily.dmg"
STAGING="/tmp/dmg_release_staging"
VOL_PATH="/Volumes/$DMG_NAME"

echo "=== Creating Release DMG ==="

# Clean up
rm -rf "$STAGING"
mkdir -p "$STAGING"

# Copy app
echo "1. Copying Release app..."
cp -R "$APP_PATH" "$STAGING/"

# Create Applications symlink
ln -s /Applications "$STAGING/Applications"

# Create read-write DMG first (for customization)
echo "2. Creating DMG..."
rm -f "$DMG_TEMP" "$DMG_OUTPUT"

hdiutil create \
    -volname "$DMG_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDRW \
    "$DMG_TEMP"

# Mount it
echo "3. Mounting for customization..."
hdiutil attach "$DMG_TEMP" -nobrowse

# Set window layout via AppleScript-friendly DS_Store
# Set icon positions and window size
echo '
   tell application "Finder"
     tell disk "Daily"
       open
       set current view of container window to icon view
       set toolbar visible of container window to false
       set statusbar visible of container window to false
       set bounds of container window to {100, 100, 640, 400}
       set viewOptions to the icon view options of container window
       set arrangement of viewOptions to not arranged
       set icon size of viewOptions to 80
       set position of item "Daily.app" of container window to {150, 150}
       set position of item "Applications" of container window to {390, 150}
       close
     end tell
   end tell
' | osascript 2>/dev/null || echo "(window layout: skipped on headless)"

sleep 1

# Unmount
echo "4. Converting to compressed DMG..."
hdiutil detach "$VOL_PATH" 2>/dev/null || true
sleep 1

# Convert to compressed read-only DMG
hdiutil convert "$DMG_TEMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_OUTPUT"

# Clean up
rm -f "$DMG_TEMP"
rm -rf "$STAGING"

echo ""
echo "=== Done! ==="
ls -lh "$DMG_OUTPUT"
echo ""
echo "SHA-256:"
shasum -a 256 "$DMG_OUTPUT"
