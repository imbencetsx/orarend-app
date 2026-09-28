# ÓrarendApp

Native macOS menu bar app. Shows the current class + time remaining; during breaks, the next class + time until the bell.

## Usage

```bash
swift test            # logic tests
./build-app.sh        # build OrarendApp.app
open ./OrarendApp.app # run (menu bar only, no dock icon)
```

Click the menu bar item for a big countdown, today's classes, and settings (launch at login, debug mode with simulated time).

## Configure

Edit `Resources/timetable.json` (bell schedule + timetable), or — once the app
has run — `~/Library/Application Support/OrarendApp/timetable.json` (the app
seeds it from the bundled file on first launch). Then press Újratöltés
(Reload) in Settings → Órarend, or restart the app.

Day keys accept `monday`…`friday` (also hungarian names or weekday numbers
`"2"`…`"6"`); times are `"H:MM"`; a `null` subject means a free period.
