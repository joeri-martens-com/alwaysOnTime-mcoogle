#!/usr/bin/env bash
# install.sh — sets up meet-opener on any Mac
# Usage: ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_LABEL="com.joeri.meet-opener"
PLIST_FILE="$PLIST_DIR/$PLIST_LABEL.plist"
SCRIPT_DEST="$INSTALL_DIR/meet-opener.py"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}▶${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✗${NC}  $*"; exit 1; }
success() { echo -e "${GREEN}✓${NC} $*"; }

echo ""
echo "  meet-opener installer"
echo "  ─────────────────────"
echo ""

# ── Check prerequisites ───────────────────────────────────────────────────────
info "Checking prerequisites..."

PYTHON=$(command -v python3 || true)
[[ -z "$PYTHON" ]] && error "python3 not found. Install it via Homebrew: brew install python"

PY_VERSION=$("$PYTHON" -c "import sys; print(sys.version_info[:2])")
"$PYTHON" -c "import sys; sys.exit(0 if sys.version_info >= (3,9) else 1)" \
    || error "Python 3.9+ required (found $PY_VERSION). Upgrade via: brew install python"

[[ ! -d "/Applications/Google Chrome.app" ]] \
    && error "Google Chrome not found at /Applications/Google Chrome.app"

success "Python $("$PYTHON" --version 2>&1 | awk '{print $2}') and Chrome found."

# ── Collect ICS URLs ──────────────────────────────────────────────────────────
echo ""
info "Enter your Google Calendar ICS URL(s)."
echo "   How to get them: Google Calendar → Settings (gear) → click a calendar"
echo "   in the left sidebar → scroll to 'Secret address in iCal format'."
echo "   Press Enter on an empty line when done."
echo ""

ICS_URLS=()
while true; do
    read -rp "  ICS URL (or Enter to finish): " url
    [[ -z "$url" ]] && break
    if [[ "$url" != https://calendar.google.com/calendar/ical/* ]]; then
        warn "That doesn't look like a Google Calendar ICS URL — skipping."
        continue
    fi
    ICS_URLS+=("$url")
    success "Added."
done

[[ ${#ICS_URLS[@]} -eq 0 ]] && error "No ICS URLs provided. Nothing to install."

# ── Install script ────────────────────────────────────────────────────────────
echo ""
info "Installing meet-opener.py to $SCRIPT_DEST ..."
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/meet-opener.py" "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"

# Inject ICS URLs into the installed copy
URL_LINES=""
for url in "${ICS_URLS[@]}"; do
    URL_LINES+="    \"$url\",\n"
done

"$PYTHON" - "$SCRIPT_DEST" "$URL_LINES" << 'PYEOF'
import sys, re
path = sys.argv[1]
url_lines = sys.argv[2]
text = open(path).read()
text = re.sub(
    r'ICS_URLS = \[.*?\]',
    f'ICS_URLS = [\n{url_lines}]',
    text, flags=re.DOTALL
)
open(path, 'w').write(text)
PYEOF

success "Script installed."

# ── Install launchd plist ─────────────────────────────────────────────────────
info "Installing launchd agent to $PLIST_FILE ..."
mkdir -p "$PLIST_DIR"

cat > "$PLIST_FILE" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$SCRIPT_DEST</string>
    </array>

    <key>StartInterval</key>
    <integer>60</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/meet_opener_stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/meet_opener_stderr.log</string>
</dict>
</plist>
PLIST

success "Plist written."

# ── Load (or reload) agent ────────────────────────────────────────────────────
info "Loading launchd agent..."
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load "$PLIST_FILE"
success "Agent loaded — runs every 60 seconds."

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "  ✅  meet-opener is running!"
echo ""
echo "  It will open Chrome + send a notification when a Google Meet"
echo "  starts within 2 minutes of its scheduled start time."
echo ""
echo "  Logs:      tail -f /tmp/meet_opener.log"
echo "  Uninstall: launchctl unload $PLIST_FILE && rm $PLIST_FILE $SCRIPT_DEST"
echo ""
