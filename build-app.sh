#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift test
swift build -c release
APP="dist/Pulau.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"
cp .build/release/Pulau "$CONTENTS/MacOS/Pulau"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Pulau</string>
<key>CFBundleIdentifier</key><string>com.robby.Pulau</string>
<key>CFBundleName</key><string>Pulau</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
if [ -n "$IDENTITY" ]; then
    echo "Signed with Apple Development identity"
else
    echo "Signed ad-hoc; Full Disk Access grants may not persist across rebuilds"
fi
printf 'Built %s\n' "$APP"
