#!/bin/bash
# Signs build/Clip.md.app with Developer ID, notarizes and staples it, and re-zips build/Clip.md.zip,
# so the GitHub release opens without Gatekeeper warnings. Run after ./build.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ASC_KEY_ID:=238ATU74S4}" "${ASC_ISSUER_ID:=98c62465-9650-49ec-afe4-23318e5c1ae1}"
app=build/Clip.md.app
codesign --force --timestamp --options runtime --sign "Developer ID Application: Adam Hitchcock (4BJBDQVY6M)" \
  --entitlements clipmd.entitlements "$app"
(cd build && rm -f Clip.md.zip && ditto -c -k --keepParent Clip.md.app Clip.md.zip)
xcrun notarytool submit build/Clip.md.zip --wait \
  --key "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
xcrun stapler staple "$app"
(cd build && rm -f Clip.md.zip && ditto -c -k --keepParent Clip.md.app Clip.md.zip)
spctl --assess --type execute -v "$app"
