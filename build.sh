#!/bin/bash
# Builds build/Clip.md.app (universal) and build/Clip.md.zip.
set -euo pipefail
cd "$(dirname "$0")"
version=$(cat VERSION)
app=build/Clip.md.app
rm -rf "$app" && mkdir -p "$app/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13" main.swift -o "build/clipmd-$arch"
done
lipo -create build/clipmd-arm64 build/clipmd-x86_64 -output "$app/Contents/MacOS/ClipMD"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.northisup.clipmd</string>
  <key>CFBundleName</key><string>Clip.md</string>
  <key>CFBundleExecutable</key><string>ClipMD</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
(cd build && rm -f Clip.md.zip && ditto -c -k --keepParent Clip.md.app Clip.md.zip)
