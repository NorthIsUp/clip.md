#!/bin/bash
# One-time, run locally: loads the signing material from ~/.appstoreconnect into this repo's Actions secrets.
set -euo pipefail
D=~/.appstoreconnect/clipmd R=NorthIsUp/clip.md
/usr/bin/openssl x509 -inform der -in "$D/devid.cer" -out "$D/devid.pem"
/usr/bin/openssl pkcs12 -export -inkey "$D/devid.key" -in "$D/devid.pem" -out "$D/devid.p12" -passout "file:$D/p12.pass" 2>/dev/null
chmod 600 "$D/devid.p12"
security import "$D/devid.p12" -k ~/Library/Keychains/login.keychain-db -P "$(cat "$D/p12.pass")" -T /usr/bin/codesign >/dev/null || true
gh secret set ASC_KEY_P8 -R $R < ~/.appstoreconnect/private_keys/AuthKey_238ATU74S4.p8
gh secret set P12_PASSWORD -R $R < "$D/p12.pass"
for name in dist installer devid; do base64 -i "$D/$name.p12" | gh secret set "$(echo $name | tr a-z A-Z)_P12" -R $R; done
base64 -i "$D/profile.provisionprofile" | gh secret set PROFILE -R $R
gh secret list -R $R
