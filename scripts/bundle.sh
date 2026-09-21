#!/bin/bash
# Builds build/Butler.app with the sidecar and its node_modules inside.
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-release}"
app="build/Butler.app"
contents="$app/Contents"

test -d Sidecar/node_modules || { echo "run 'bun install' in Sidecar/ first" >&2; exit 1; }
bash Sidecar/scripts/build.sh >/dev/null
swift build -c "$configuration"
binary="$(swift build -c "$configuration" --show-bin-path)/ButlerApp"

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$binary" "$contents/MacOS/Butler"

mkdir -p "$contents/Resources/Sidecar"
cp Sidecar/package.json Sidecar/bunfig.toml Sidecar/host.mjs "$contents/Resources/Sidecar/"
cp -R Sidecar/node_modules "$contents/Resources/Sidecar/node_modules"

if [ -f build/Butler.icns ]; then
  cp build/Butler.icns "$contents/Resources/Butler.icns"
fi


cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Butler</string>
  <key>CFBundleDisplayName</key><string>Butler</string>
  <key>CFBundleIdentifier</key><string>com.serhiitroinin.butler</string>
  <key>CFBundleExecutable</key><string>Butler</string>
  <key>CFBundleIconFile</key><string>Butler</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT licensed.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app" >/dev/null 2>&1 || echo "note: ad-hoc signing failed; the app still runs locally"
echo "built $(pwd)/$app"
