#!/bin/bash
# Builds build/LidAwake.app with plain swiftc (Command Line Tools are enough) and signs it ad hoc.
set -euo pipefail

cd "$(dirname "$0")"

APP="build/LidAwake.app"
CONTENTS="$APP/Contents"
BIN="$CONTENTS/MacOS/LidAwake"
MIN_OS="14.0"
SDK="$(xcrun --show-sdk-path)"

shopt -s nullglob
SOURCES=(Sources/*.swift)
if [ ${#SOURCES[@]} -eq 0 ]; then
    echo "error: no Swift files in Sources/" >&2
    exit 1
fi

rm -rf "$APP" build/obj
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" build/obj

compile() {
    local arch="$1"
    swiftc -O -swift-version 5 \
        -sdk "$SDK" \
        -target "$arch-apple-macos$MIN_OS" \
        -module-name LidAwake \
        -framework AppKit -framework IOKit \
        -o "build/obj/LidAwake-$arch" \
        "${SOURCES[@]}"
}

echo "==> compiling arm64"
compile arm64

echo "==> compiling x86_64"
if compile x86_64; then
    lipo -create build/obj/LidAwake-arm64 build/obj/LidAwake-x86_64 -output "$BIN"
else
    echo "warning: x86_64 build failed, shipping arm64 only" >&2
    cp build/obj/LidAwake-arm64 "$BIN"
fi

echo "==> writing Info.plist"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>LidAwake</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>space.thelaunch.lidawake</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LidAwake</string>
    <key>CFBundleDisplayName</key>
    <string>LidAwake</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 thelaunch.space</string>
</dict>
</plist>
PLIST
plutil -lint "$CONTENTS/Info.plist"

echo "==> copying Resources"
copied=0
if [ -d Resources ]; then
    for f in Resources/*; do
        [ -f "$f" ] || continue
        cp "$f" "$CONTENTS/Resources/"
        copied=$((copied + 1))
    done
fi
for f in "$CONTENTS/Resources"/*.sh; do
    chmod +x "$f"
done
echo "copied $copied resource file(s)"

echo "==> signing (ad hoc)"
codesign --force --sign - --timestamp=none "$APP"

rm -rf build/obj
echo "==> built $APP ($(lipo -archs "$BIN"))"
