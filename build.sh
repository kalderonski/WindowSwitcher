#!/bin/zsh
# Builds WindowSwitcher.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP=build/WindowSwitcher.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/WindowSwitcher"

ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
swiftc tools/make_icon.swift -o build/make_icon
build/make_icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>WindowSwitcher</string>
  <key>CFBundleDisplayName</key><string>Window Switcher</string>
  <key>CFBundleIdentifier</key><string>com.example.WindowSwitcher</string>
  <key>CFBundleExecutable</key><string>WindowSwitcher</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
EOF

# Stable identity (see tools/setup_signing.sh) keeps privacy permissions across rebuilds.
IDENTITY="WindowSwitcher Local Signing"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: no stable signing identity; run tools/setup_signing.sh (permissions will reset on every rebuild)"
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
