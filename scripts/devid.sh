#!/bin/bash
# Signs build/Clip.md.app with Developer ID, notarizes and staples it, then builds a notarized
# build/Clip.md.dmg (and re-zips build/Clip.md.zip) so GitHub downloads open without Gatekeeper warnings.
# Run after ./build.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ASC_KEY_ID:=238ATU74S4}" "${ASC_ISSUER_ID:=98c62465-9650-49ec-afe4-23318e5c1ae1}"
app=build/Clip.md.app
codesign --force --timestamp --options runtime --sign "Developer ID Application: Adam Hitchcock (4BJBDQVY6M)" \
  --entitlements clipmd.entitlements "$app"
(cd build && rm -f Clip.md.zip && ditto -c -k --keepParent Clip.md.app Clip.md.zip)
notarize() { xcrun notarytool submit "$1" --wait \
  --key "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"; }
notarize build/Clip.md.zip
xcrun stapler staple "$app"
(cd build && rm -f Clip.md.zip && ditto -c -k --keepParent Clip.md.app Clip.md.zip)
spctl --assess --type execute -v "$app"

rm -rf build/dmg build/Clip.md.dmg && mkdir build/dmg && cp -R "$app" build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -quiet -volname Clip.md -srcfolder build/dmg -format UDZO build/Clip.md.dmg
codesign --timestamp --sign "Developer ID Application: Adam Hitchcock (4BJBDQVY6M)" build/Clip.md.dmg
notarize build/Clip.md.dmg
xcrun stapler staple build/Clip.md.dmg
spctl --assess --type open --context context:primary-signature -v build/Clip.md.dmg
