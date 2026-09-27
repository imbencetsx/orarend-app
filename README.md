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

Edit the bell schedule + timetable in `Sources/OrarendApp/Schedule.swift`.
