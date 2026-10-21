#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v rsvg-convert >/dev/null || { echo 'Regenerating icons requires librsvg (rsvg-convert).' >&2; exit 1; }
brand=extensions/capture/Sources/CaptureMac/Resources/Brand
for entry in '16x16:16:small' '16x16@2x:32:small' '32x32:32:small' '32x32@2x:64:small' \
             '128x128:128:regular' '128x128@2x:256:regular' '256x256:256:regular' \
             '256x256@2x:512:regular' '512x512:512:regular' '512x512@2x:1024:regular'; do
    IFS=: read -r name pixels geometry <<< "$entry"
    source="$brand/AppIcon.svg"
    if [[ "$geometry" == small ]]; then source="$brand/AppIconSmall.svg"; fi
    rsvg-convert -w "$pixels" -h "$pixels" "$source" -o "$brand/AppIcon.iconset/icon_$name.png"
done
