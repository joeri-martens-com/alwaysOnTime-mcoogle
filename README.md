# meet-opener

Automatically opens Google Meet links in Chrome the moment a meeting starts — no more missing the 15-minute pop-up.

Runs silently in the background on macOS via launchd. Checks your Google Calendar every minute and opens Chrome + plays a notification sound when a meeting is about to start.

## Requirements

- macOS
- Python 3.9+ (`brew install python` if needed)
- Google Chrome

## Install

```bash
git clone https://github.com/joeri-martens-com/alwaysOnTime-mcoogle.git
cd alwaysOnTime-mcoogle
./install.sh
```

The installer will ask for one or more Google Calendar ICS URLs (see below), then wires everything up automatically.

## Getting your ICS URL

You need one URL per calendar you want monitored.

1. Open [calendar.google.com](https://calendar.google.com)
2. Click the gear icon → **Settings**
3. In the left sidebar, click a calendar name (under "My calendars" or "Other calendars")
4. Scroll down to **"Secret address in iCal format"**
5. Copy the URL and paste it when prompted by `install.sh`

Repeat for each calendar (e.g. your primary calendar + any team calendars).

## How it works

- A launchd agent runs `meet-opener.py` every 60 seconds
- It fetches your ICS feeds (today only, so it's fast)
- If a meeting with a `meet.google.com` link starts within 2 minutes, Chrome opens it and you get a macOS notification
- Each meeting is only opened once per day

## Logs

```bash
tail -f /tmp/meet_opener.log
```

## Adding more calendars

Open `~/.local/bin/meet-opener.py` and add URLs to the `ICS_URLS` list. No restart needed.

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.joeri.meet-opener.plist
rm ~/Library/LaunchAgents/com.joeri.meet-opener.plist
rm ~/.local/bin/meet-opener.py
```
