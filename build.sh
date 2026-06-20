#!/bin/bash
set -e

APP_NAME="VolumeScroll"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Compile
swiftc VolumeScroll.swift \
    -o "$MACOS_DIR/$APP_NAME" \
    -framework Cocoa \
    -framework CoreAudio \
    -framework ApplicationServices \
    -O

# App icon (used for the bundle and shown in the About window)
cp VolumeScroll.icns "$RESOURCES_DIR/VolumeScroll.icns"

# Info.plist — LSUIElement makes it an agent (menu-bar-only) app
cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>Volume Scroll</string>
    <key>CFBundleIdentifier</key><string>com.local.$APP_NAME</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>VolumeScroll</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# Ad-hoc sign so the Accessibility grant sticks across launches
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
echo "Run it with:  open \"$APP_BUNDLE\""
