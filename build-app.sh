#!/bin/zsh
# Builds a release FakeOS.app in ./dist
set -e
cd "${0:h}"
swift build -c release
mkdir -p Assets
APP=dist/FakeOS.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FakeOS "$APP/Contents/MacOS/FakeOS"
ICONSET=$(mktemp -d)/AppIcon.iconset
.build/release/FakeOS --export-icon "$ICONSET" --preview Assets/AppIcon.png
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Fake OS</string>
  <key>CFBundleIdentifier</key><string>local.fakeos.game</string>
  <key>CFBundleExecutable</key><string>FakeOS</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
