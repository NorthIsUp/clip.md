#!/bin/bash
# Each fixtures/*.html must convert to its sibling .md.
set -euo pipefail
cd "$(dirname "$0")"
bin=build/Clip.md.app/Contents/MacOS/ClipMD
[ -x "$bin" ] || ./build.sh
for html in fixtures/*.html; do
  diff -u "${html%.html}.md" <("$bin" --convert < "$html") && echo "ok $html"
done
# Raw org.chromium.web-custom-data blobs (Slack "Copy message").
for wcd in fixtures/*.wcd; do
  diff -u "${wcd%.wcd}.md" <("$bin" --convert-web-custom-data < "$wcd") && echo "ok $wcd"
done
