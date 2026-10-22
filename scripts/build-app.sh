#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${CONFIGURATION:-release}"
bundle_id="${BUNDLE_ID:-dev.inkcre.capture}"
development_identity="${DEVELOPMENT_SIGNING_IDENTITY:-}"
if [[ -z "$development_identity" && -z "${SIGNING_IDENTITY:-}" && -f .local-development-signing-identity ]]; then
  development_identity="$(< .local-development-signing-identity)"
fi
version="0.1.0"
case "$bundle_id" in *[!a-zA-Z0-9.-]*|"") echo "Invalid BUNDLE_ID" >&2; exit 1;; esac
if [[ -n "${SIGNING_IDENTITY:-}" && "$bundle_id" == dev.* ]]; then
  echo "Signed release builds require an explicit stable BUNDLE_ID outside dev.*." >&2
  exit 1
fi
if [[ -n "${SIGNING_IDENTITY:-}" && -n "$development_identity" ]]; then
  echo "Choose either development signing or release signing, not both." >&2
  exit 1
fi

swift build -c "$configuration" --arch arm64 --arch x86_64
bin_path="$(swift build -c "$configuration" --arch arm64 --arch x86_64 --show-bin-path)"
app="dist/InKCre.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp "$bin_path/InKCre" "$app/Contents/MacOS/InKCre"
cp -R "$bin_path/InKCreCapture_Capture.bundle" "$app/Contents/Resources/"
cp -R "$bin_path/InKCreCapture_CaptureMac.bundle" "$app/Contents/Resources/"
for resource in "$bin_path"/swift-*.bundle; do
  [[ -d "$resource" ]] || continue
  cp -R "$resource" "$app/Contents/Resources/"
done
python3 scripts/collect-licenses.py "$app/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp LICENSE "$app/Contents/Resources/LICENSE"
iconutil -c icns extensions/capture/Sources/CaptureMac/Resources/Brand/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>InKCre</string>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>InKCre</string>
<key>CFBundleDisplayName</key><string>InKCre</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>12</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAccessibilityUsageDescription</key><string>仅在你唤起采集时读取当前选区与可获得的出处。</string>
<key>NSScreenCaptureUsageDescription</key><string>保存你明确框选的屏幕区域。</string>
</dict></plist>
PLIST
touch "$app"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
elif [[ -n "$development_identity" ]]; then
  codesign --force --sign "$development_identity" "$app"
else
  echo "Ad-hoc signing: screen-recording grants may reset after code changes. Use DEVELOPMENT_SIGNING_IDENTITY for a stable local build." >&2
  codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/InKCre.app"
ln -s /Applications "$staging/Applications"
dmg="dist/InKCre-$version-universal.dmg"
hdiutil create -quiet -volname InKCre -srcfolder "$staging" -format UDZO -ov "$dmg"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ -n "${SIGNING_IDENTITY:-}" ]] || { echo "Notarization requires SIGNING_IDENTITY" >&2; exit 1; }
  xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg"
fi
echo "$PWD/$app"
echo "$PWD/$dmg"
