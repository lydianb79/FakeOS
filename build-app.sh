#!/bin/zsh
# Builds a release FakeOS.app in ./dist
set -e
cd "${0:h}"
swift build -c release
APP=dist/FakeOS.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/FakeOS "$APP/Contents/MacOS/FakeOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Fake OS</string>
  <key>CFBundleIdentifier</key><string>local.fakeos.game</string>
  <key>CFBundleExecutable</key><string>FakeOS</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
