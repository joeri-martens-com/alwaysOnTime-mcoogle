# install.ps1 — sets up meet-opener on Windows
# Usage: Right-click → "Run with PowerShell", or: powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = "$env:LOCALAPPDATA\meet-opener"
$ScriptDest = "$InstallDir\meet-opener.py"
$TaskName   = "meet-opener"

# ── Colours ───────────────────────────────────────────────────────────────────
function Info    { param($m) Write-Host "▶ $m" -ForegroundColor Cyan }
function Success { param($m) Write-Host "✓ $m" -ForegroundColor Green }
function Warn    { param($m) Write-Host "⚠ $m" -ForegroundColor Yellow }
function Err     { param($m) Write-Host "✗ $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  meet-opener installer (Windows)" -ForegroundColor White
Write-Host "  ────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ── Check prerequisites ───────────────────────────────────────────────────────
Info "Checking prerequisites..."

$Python = (Get-Command python -ErrorAction SilentlyContinue)?.Source
if (-not $Python) { Err "Python not found. Install from https://python.org (check 'Add to PATH')." }

$PyVer = & $Python -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')"
if ([int]$PyVer -lt 39) { Err "Python 3.9+ required. Download from https://python.org." }

$ChromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
)
$Chrome = $ChromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Chrome) { Err "Google Chrome not found." }

Success "Python and Chrome found."

# ── Collect ICS URLs ──────────────────────────────────────────────────────────
Write-Host ""
Info "Enter your Google Calendar ICS URL(s)."
Write-Host "   How to get them: Google Calendar → Settings (gear) → click a calendar"
Write-Host "   in the left sidebar → scroll to 'Secret address in iCal format'."
Write-Host "   Press Enter on an empty line when done."
Write-Host ""

$IcsUrls = @()
while ($true) {
    $url = Read-Host "  ICS URL (or Enter to finish)"
    if ([string]::IsNullOrWhiteSpace($url)) { break }
    if ($url -notlike "https://calendar.google.com/calendar/ical/*") {
        Warn "That doesn't look like a Google Calendar ICS URL — skipping."
        continue
    }
    $IcsUrls += $url
    Success "Added."
}

if ($IcsUrls.Count -eq 0) { Err "No ICS URLs provided. Nothing to install." }

# ── Install script ────────────────────────────────────────────────────────────
Write-Host ""
Info "Installing meet-opener.py to $ScriptDest ..."
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item "$ScriptDir\meet-opener.py" $ScriptDest -Force

# Inject ICS URLs into the installed copy
$urlLines = ($IcsUrls | ForEach-Object { "    `"$_`"," }) -join "`n"
$content  = Get-Content $ScriptDest -Raw
$content  = $content -replace '(?s)ICS_URLS = \[.*?\]', "ICS_URLS = [`n$urlLines`n]"
Set-Content $ScriptDest $content -Encoding UTF8

Success "Script installed."

# ── Register Task Scheduler job ───────────────────────────────────────────────
Info "Registering Task Scheduler job '$TaskName' (runs every minute)..."

# Prefer pythonw.exe (no console window); fall back to python.exe
$PythonW = Join-Path (Split-Path $Python) "pythonw.exe"
if (-not (Test-Path $PythonW)) { $PythonW = $Python }

# Remove existing task if present
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action   = New-ScheduledTaskAction -Execute $PythonW -Argument "`"$ScriptDest`""
$Trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date)
$Trigger.Repetition.Interval = "PT1M"   # repeat every 1 minute
$Trigger.Repetition.Duration = ""       # indefinitely
$Settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit    (New-TimeSpan -Minutes 1) `
    -MultipleInstances     IgnoreNew `
    -StartWhenAvailable    $true

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action   $Action `
    -Trigger  $Trigger `
    -Settings $Settings `
    -RunLevel Highest `
    -Force | Out-Null

Success "Task registered — runs every 60 seconds."

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ✅  meet-opener is running!" -ForegroundColor Green
Write-Host ""
Write-Host "  It will open Chrome + show a notification when a Google Meet"
Write-Host "  starts within 2 minutes of its scheduled start time."
Write-Host ""
Write-Host "  Logs:      $env:TEMP\meet_opener.log"
Write-Host "  Uninstall: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
Write-Host "             Remove-Item '$ScriptDest' -Force"
Write-Host ""
