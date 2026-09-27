#!/bin/bash
# Re-signs a copy of build/Clip.md.app for the Mac App Store, packages build/Clip.md.pkg, and uploads it to TestFlight.
# Needs the Apple Distribution + Mac Installer identities in a keychain, the MAS profile at $PROFILE,
# and the App Store Connect key at ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8.
# --no-upload stops after packaging.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ASC_KEY_ID:=238ATU74S4}" "${ASC_ISSUER_ID:=98c62465-9650-49ec-afe4-23318e5c1ae1}"
: "${PROFILE:=$HOME/.appstoreconnect/clipmd/profile.provisionprofile}"
team=4BJBDQVY6M
app=build/appstore/Clip.md.app pkg=build/Clip.md.pkg

# The copy keeps build/Clip.md.app runnable here; an App Store signature only runs once installed from the store.
BUILD_NUMBER=${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)} ./build.sh
rm -rf build/appstore && mkdir -p build/appstore && cp -R build/Clip.md.app "$app"
cp "$PROFILE" "$app/Contents/embedded.provisionprofile"
cp clipmd.entitlements build/appstore.entitlements
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $team.com.northisup.clipmd" \
  -c "Add :com.apple.developer.team-identifier string $team" build/appstore.entitlements
codesign --force --timestamp --options runtime --sign "Apple Distribution: Adam Hitchcock ($team)" \
  --entitlements build/appstore.entitlements "$app"
productbuild --component "$app" /Applications --sign "3rd Party Mac Developer Installer: Adam Hitchcock ($team)" "$pkg"
pkgutil --check-signature "$pkg" | head -3

[ "${1:-}" = --no-upload ] && exit 0
xcrun altool --upload-app -f "$pkg" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
