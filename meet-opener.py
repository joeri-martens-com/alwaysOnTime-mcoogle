#!/usr/bin/env python3
"""
meet-opener.py
Runs every minute (via launchd on macOS, Task Scheduler on Windows).
Fetches Google Calendar ICS feeds, finds meetings starting within
LOOK_AHEAD_MINUTES, and opens them in Chrome.

Setup: run install.sh (macOS) or install.ps1 (Windows).
"""

import os
import re
import ssl
import subprocess
import sys
import tempfile
import urllib.request
from datetime import datetime, timezone, timedelta

# ── Config (filled in by install.sh / install.ps1) ───────────────────────────

ICS_URLS = [
    # "https://calendar.google.com/calendar/ical/YOUR_SECRET_URL/basic.ics",
]

LOOK_AHEAD_MINUTES = 2  # open the link up to N minutes before start

# ── Platform helpers ──────────────────────────────────────────────────────────

def find_chrome():
    if sys.platform == 'darwin':
        return '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    if sys.platform == 'win32':
        candidates = [
            os.path.expandvars(r'%ProgramFiles%\Google\Chrome\Application\chrome.exe'),
            os.path.expandvars(r'%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe'),
            os.path.expandvars(r'%LocalAppData%\Google\Chrome\Application\chrome.exe'),
        ]
        for path in candidates:
            if os.path.exists(path):
                return path
    return None

def notify(title, message):
    if sys.platform == 'darwin':
        subprocess.run(
            ['osascript', '-e',
             f'display notification "{message}" with title "{title}" sound name "Blow"'],
            check=False,
        )
    elif sys.platform == 'win32':
        ps = (
            '[reflection.assembly]::loadwithpartialname("System.Windows.Forms") | Out-Null;'
            '[reflection.assembly]::loadwithpartialname("System.Drawing") | Out-Null;'
            '$n = New-Object System.Windows.Forms.NotifyIcon;'
            '$n.Icon = [System.Drawing.SystemIcons]::Information;'
            '$n.Visible = $true;'
            f'$n.ShowBalloonTip(5000, "{title}", "{message}", '
            '[System.Windows.Forms.ToolTipIcon]::Info)'
        )
        subprocess.run(['powershell', '-NoProfile', '-Command', ps],
                       check=False, capture_output=True)

_TEMP = tempfile.gettempdir()
LOCK_FILE = os.path.join(_TEMP, 'meet_opener_opened.txt')
LOG_FILE  = os.path.join(_TEMP, 'meet_opener.log')

# ── ICS fetching ──────────────────────────────────────────────────────────────

def fetch(url):
    today    = datetime.now(timezone.utc).date()
    tomorrow = today + timedelta(days=1)
    sep = '&' if '?' in url else '?'
    url = f"{url}{sep}start-min={today.isoformat()}&start-max={tomorrow.isoformat()}"
    # Corporate SSL inspection proxies use a self-signed CA; skip verification for this read-only feed.
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url, headers={"User-Agent": "MeetOpener/1.0"})
    with urllib.request.urlopen(req, context=ctx, timeout=10) as r:
        return r.read().decode("utf-8", errors="replace")

# ── ICS parsing ───────────────────────────────────────────────────────────────

def unfold(text):
    """Rejoin RFC 5545 folded lines."""
    return re.sub(r'\r?\n[ \t]', '', text)

def parse_dt(value, tzid=None):
    """Return a UTC-aware datetime, or None for all-day / unparseable."""
    value = value.strip()
    if value.endswith('Z'):
        return datetime.strptime(value, '%Y%m%dT%H%M%SZ').replace(tzinfo=timezone.utc)
    if 'T' not in value:
        return None  # all-day
    naive = datetime.strptime(value, '%Y%m%dT%H%M%S')
    if tzid:
        try:
            from zoneinfo import ZoneInfo
            return naive.replace(tzinfo=ZoneInfo(tzid))
        except Exception:
            pass
    return naive.astimezone(timezone.utc)

def parse_events(ics_text):
    ics_text = unfold(ics_text)
    # key: (date, meet_url) → keep only the highest DTSTART (modified occurrences
    # override the original recurring slot when the event was rescheduled)
    best: dict = {}

    for block in re.split(r'BEGIN:VEVENT', ics_text)[1:]:
        block = block.split('END:VEVENT')[0]

        m = re.search(r'DTSTART(?:;TZID=([^:;]+))?(?:;[^:]+)?:([^\r\n]+)', block)
        if not m:
            continue
        start = parse_dt(m.group(2), m.group(1))
        if start is None:
            continue

        summary_m = re.search(r'^SUMMARY:([^\r\n]+)', block, re.MULTILINE)
        summary = summary_m.group(1).strip() if summary_m else 'Meeting'

        meet_m = re.search(r'https://meet\.google\.com/([\w-]+)', block)
        if not meet_m:
            continue

        event = {
            'start':   start,
            'summary': summary,
            'url':     f"https://meet.google.com/{meet_m.group(1)}",
        }
        key = (start.date(), event['url'])
        if key not in best or start > best[key]['start']:
            best[key] = event

    return list(best.values())

# ── State helpers ─────────────────────────────────────────────────────────────

def load_opened():
    opened = set()
    if not os.path.exists(LOCK_FILE):
        return opened
    today = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    with open(LOCK_FILE) as f:
        for line in f:
            parts = line.strip().split('|', 1)
            if len(parts) == 2 and parts[0] == today:
                opened.add(parts[1])
    return opened

def mark_opened(uid):
    today = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    with open(LOCK_FILE, 'a') as f:
        f.write(f"{today}|{uid}\n")

def log(msg):
    ts = datetime.now(timezone.utc).isoformat(timespec='seconds')
    with open(LOG_FILE, 'a') as f:
        f.write(f"{ts}  {msg}\n")

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    if not ICS_URLS:
        log("No ICS_URLS configured — nothing to do.")
        return

    chrome = find_chrome()
    if not chrome:
        log("Chrome not found.")
        return

    now    = datetime.now(timezone.utc)
    opened = load_opened()

    for ics_url in ICS_URLS:
        try:
            ics_text = fetch(ics_url)
        except Exception as e:
            log(f"Fetch error ({ics_url[:60]}…): {e}")
            continue

        for event in parse_events(ics_text):
            minutes_until = (event['start'] - now).total_seconds() / 60
            uid = f"{event['start'].isoformat()}|{event['url']}"

            if -1 <= minutes_until <= LOOK_AHEAD_MINUTES and uid not in opened:
                if sys.platform == 'darwin':
                    script = (
                        f'tell application "Google Chrome"\n'
                        f'  set w to make new window\n'
                        f'  set URL of active tab of w to "{event["url"]}"\n'
                        f'  activate\n'
                        f'end tell'
                    )
                    subprocess.Popen(['osascript', '-e', script])
                else:
                    subprocess.Popen([chrome, '--new-window', event['url']])
                notify("Google Meet opening now!", event['summary'])
                mark_opened(uid)
                log(f"Opened: {event['summary']}  {event['url']}")
            elif -1 <= minutes_until <= LOOK_AHEAD_MINUTES:
                log(f"Skipped (already opened): {event['summary']}  {event['url']}")

if __name__ == '__main__':
    main()
