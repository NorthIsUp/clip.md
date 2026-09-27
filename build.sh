#!/bin/bash
# Builds build/Clip.md.app (universal, sandboxed, ad-hoc signed) and build/Clip.md.zip.
# BUILD_NUMBER overrides CFBundleVersion; App Store uploads need it to increase.
set -euo pipefail
cd "$(dirname "$0")"
version=$(cat VERSION)
app=build/Clip.md.app
rm -rf "$app" && mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13" main.swift -o "build/clipmd-$arch"
done
lipo -create build/clipmd-arm64 build/clipmd-x86_64 -output "$app/Contents/MacOS/ClipMD"
cp docs/AppIcon.icns "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.northisup.clipmd</string>
  <key>CFBundleName</key><string>Clip.md</string>
  <key>CFBundleDisplayName</key><string>Clip.md</string>
  <key>CFBundleExecutable</key><string>ClipMD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER:-$version}</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
</dict></plist>
PLIST
codesign --force --sign - --entitlements clipmd.entitlements "$app"
(cd build && rm -f Clip.md.zip && ditto -c -k --keepParent Clip.md.app Clip.md.zip)
