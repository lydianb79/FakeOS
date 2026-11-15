#!/bin/zsh
# Builds a release FakeOS.app in ./dist
set -e
cd "${0:h}"
VERSION=${VERSION:-1.0.0}
BUILD=$(date +%Y%m%d%H%M)
swift build -c release --arch arm64 --arch x86_64
mkdir -p Assets
APP=dist/FakeOS.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FakeOS "$APP/Contents/MacOS/FakeOS"
# App icon: render it from code, then compile an asset catalog (Assets.car + AppIcon.icns),
# the same way Xcode ships icons, so Finder/Dock pick it up on every macOS version.
WORK=$(mktemp -d)
ICONSET="$WORK/AppIcon.iconset"
.build/release/FakeOS --export-icon "$ICONSET" --preview Assets/AppIcon.png
XCASSETS="$WORK/Assets.xcassets"
mkdir -p "$XCASSETS/AppIcon.appiconset"
cp "$ICONSET"/*.png "$XCASSETS/AppIcon.appiconset/"
cat > "$XCASSETS/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
cat > "$XCASSETS/AppIcon.appiconset/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
xcrun actool "$XCASSETS" --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 13.0 \
    --app-icon AppIcon --output-partial-info-plist "$WORK/partial.plist" --output-format human-readable-text >/dev/null
# fallback for anything that only reads the legacy key
[ -f "$APP/Contents/Resources/AppIcon.icns" ] || iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Fake OS</string>
  <key>CFBundleIdentifier</key><string>io.github.lydianb79.fakeos</string>
  <key>CFBundleExecutable</key><string>FakeOS</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleDisplayName</key><string>Fake OS</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.puzzle-games</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
# refresh LaunchServices so a rebuilt app at the same path shows its icon
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
(cd dist && rm -f FakeOS.zip && ditto -c -k --keepParent FakeOS.app FakeOS.zip)
echo "Built $APP and dist/FakeOS.zip (v$VERSION build $BUILD, $(lipo -archs "$APP/Contents/MacOS/FakeOS"))"
