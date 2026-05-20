# meet-opener

Automatically opens Google Meet links in Chrome the moment a meeting starts — no more missing the 15-minute pop-up.

Runs silently in the background. Checks your Google Calendar every minute and opens Chrome + sends a notification when a meeting is about to start.

## Requirements

- macOS or Windows
- Python 3.9+
  - macOS: `brew install python`
  - Windows: [python.org](https://python.org) — check "Add to PATH" during install
- Google Chrome

## Install

**macOS:**
```bash
git clone https://github.com/joeri-martens-com/alwaysOnTime-mcoogle.git
cd alwaysOnTime-mcoogle
./install.sh
```

**Windows** (PowerShell):
```powershell
git clone https://github.com/joeri-martens-com/alwaysOnTime-mcoogle.git
cd alwaysOnTime-mcoogle
powershell -ExecutionPolicy Bypass -File install.ps1
```

The installer will ask for one or more Google Calendar ICS URLs (see below), then wires everything up automatically.

## Getting your ICS URL

You need one URL per calendar you want monitored.

1. Open [calendar.google.com](https://calendar.google.com)
2. Click the gear icon → **Settings**
3. In the left sidebar, click a calendar name (under "My calendars" or "Other calendars")
4. Scroll down to **"Secret address in iCal format"**
5. Copy the URL and paste it when prompted by the installer

Repeat for each calendar (e.g. your primary calendar + any team calendars).

## How it works

- **macOS:** a launchd agent runs `meet-opener.py` every 60 seconds
- **Windows:** a Task Scheduler job runs `meet-opener.py` every 60 seconds
- It fetches your ICS feeds (today only, so it's fast)
- If a meeting with a `meet.google.com` link starts within 2 minutes, Chrome opens it and you get a notification
- Each meeting is only opened once per day

## Logs

**macOS:**
```bash
tail -f /tmp/meet_opener.log
```

**Windows:**
```powershell
Get-Content "$env:TEMP\meet_opener.log" -Wait
```

## Adding more calendars

Add ICS URLs to the `ICS_URLS` list in the installed script. No restart needed.

- macOS: `~/.local/bin/meet-opener.py`
- Windows: `%LOCALAPPDATA%\meet-opener\meet-opener.py`

## Uninstall

**macOS:**
```bash
launchctl unload ~/Library/LaunchAgents/com.joeri.meet-opener.plist
rm ~/Library/LaunchAgents/com.joeri.meet-opener.plist
rm ~/.local/bin/meet-opener.py
```

**Windows:**
```powershell
Unregister-ScheduledTask -TaskName "meet-opener" -Confirm:$false
Remove-Item "$env:LOCALAPPDATA\meet-opener" -Recurse -Force
```
