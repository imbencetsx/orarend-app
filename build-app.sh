#!/bin/bash
# OrarendApp build: SwiftPM release → kattintható .app (dock-ikon nélkül, menübar-only)
set -euo pipefail
cd "$(dirname "$0")"

echo "→ swift build -c release"
swift build -c release

APP="OrarendApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/OrarendApp" "$APP/Contents/MacOS/OrarendApp"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/timetable.json" "$APP/Contents/Resources/timetable.json"
chmod +x "$APP/Contents/MacOS/OrarendApp"

echo "✅ Kész: ./$APP"
echo "   Indítás: open ./$APP"
echo "   Tipp: tedd a Beállítások → Általános → Bejelentkezési tételek közé,"
echo "   vagy pipáld be az app menüjében: Indítás bejelentkezéskor."
