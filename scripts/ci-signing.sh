#!/bin/bash
# CI only: installs the App Store Connect key, MAS profile and signing identities from secrets.
set -euo pipefail
: "${ASC_KEY_P8:?}" "${DIST_P12:?}" "${INSTALLER_P12:?}" "${P12_PASSWORD:?}" "${PROFILE:?}" "${RUNNER_TEMP:?}"
mkdir -p ~/.appstoreconnect/private_keys ~/.appstoreconnect/clipmd
printf '%s' "$ASC_KEY_P8" > ~/.appstoreconnect/private_keys/AuthKey_238ATU74S4.p8
printf '%s' "$PROFILE" | base64 -D > ~/.appstoreconnect/clipmd/profile.provisionprofile

keychain="$RUNNER_TEMP/signing.keychain-db" pass=$(uuidgen)
security create-keychain -p "$pass" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$pass" "$keychain"
# Identities read as invalid until the WWDR intermediate is in the keychain too.
curl -fsSL -o "$RUNNER_TEMP/wwdr.cer" https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
security import "$RUNNER_TEMP/wwdr.cer" -k "$keychain"
for p12 in "$DIST_P12" "$INSTALLER_P12" ${DEVID_P12:+"$DEVID_P12"}; do
  printf '%s' "$p12" | base64 -D > "$RUNNER_TEMP/id.p12"
  security import "$RUNNER_TEMP/id.p12" -f pkcs12 -k "$keychain" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/productbuild
done
rm "$RUNNER_TEMP/id.p12"
security set-key-partition-list -S apple-tool:,apple: -k "$pass" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" login.keychain-db
