#!/bin/bash
# Builds Lumen in release mode and wraps it into a double-clickable Lumen.app
#
# The AI service key is baked into the app bundle at build time so end users
# never configure anything. It is read from (in order):
#   1. $LUMEN_AI_KEY environment variable
#   2. the local machine's saved key (defaults com.lumen.launcher groqAPIKey)
# The key is NEVER committed to the repository.
set -e
cd "$(dirname "$0")"

# Comma-separated pool of AI service keys. Installs are spread across the
# pool and the app rotates keys automatically on rate limits.
#   LUMEN_AI_KEYS="key1,key2,key3" ./make-app.sh
AI_KEYS="${LUMEN_AI_KEYS:-${LUMEN_AI_KEY:-$(defaults read com.lumen.launcher groqAPIKey 2>/dev/null || true)}}"
if [ -z "$AI_KEYS" ]; then
    echo "warning: no AI keys found (set LUMEN_AI_KEYS) — building without built-in AI access"
fi

KEYS_XML=""
IFS=',' read -ra KEY_ARR <<< "$AI_KEYS"
for k in "${KEY_ARR[@]}"; do
    k="$(echo "$k" | xargs)"
    [ -n "$k" ] && KEYS_XML="${KEYS_XML}        <string>${k}</string>
"
done

swift build -c release

APP="Lumen.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Lumen "$APP/Contents/MacOS/Lumen"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Lumen</string>
    <key>CFBundleIdentifier</key>
    <string>com.lumen.launcher</string>
    <key>CFBundleName</key>
    <string>Lumen</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Lumen uses automation for system commands like Empty Trash and Toggle Dark Mode.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Lumen captures screenshots so you can ask AI questions about what's on your screen.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Lumen shows your upcoming events in the launcher and widgets.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Lumen shows your upcoming events in the launcher and widgets.</string>
    <key>NSRemindersUsageDescription</key>
    <string>Lumen shows due reminders and creates new ones from the launcher.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Lumen shows due reminders and creates new ones from the launcher.</string>
    <key>LumenAIKeys</key>
    <array>
${KEYS_XML}    </array>
</dict>
</plist>
EOF

codesign --force -s - "$APP"
echo "Built $APP — run with: open $APP"
