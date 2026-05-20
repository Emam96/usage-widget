# Claude Code Usage Widget — Installer
# Run this once. It sets up everything and auto-starts at every boot.

$ErrorActionPreference = "Stop"

$WidgetDir = "$env:USERPROFILE\ClaudeUsageWidget"
$ClaudeDir = "$env:USERPROFILE\.claude"
$PythonMin = [Version]"3.8"

# GitHub source
$GitHubBase = "https://raw.githubusercontent.com/Emam96/usage-widget/master"

# Only available when script runs from local disk
$ScriptDir = $null

if ($PSCommandPath) {
    $ScriptDir = Split-Path -Parent $PSCommandPath
}

function Write-Step($msg) {
    Write-Host "`n>> $msg" -ForegroundColor Cyan
}

function Write-OK($msg) {
    Write-Host "   OK  $msg" -ForegroundColor Green
}

function Fail($msg) {
    Write-Host "`n   ERROR: $msg" -ForegroundColor Red
    exit 1
}

function Get-TextFile($filename) {

    # Try local repo files first (only if running locally)
    if ($ScriptDir) {

        $local = Join-Path $ScriptDir $filename

        if (Test-Path $local) {
            return Get-Content $local -Raw -Encoding utf8
        }
    }

    # Otherwise download from GitHub
    try {

        $url = "$GitHubBase/$filename"

        Write-Host "   Downloading $filename..."

        return (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
    }
    catch {
        Fail "Could not get $filename from GitHub: $_"
    }
}

# ── 1. Find Python ────────────────────────────────────────────────────────────

Write-Step "Checking Python..."

$python = $null

foreach ($cmd in @("python", "python3", "py")) {

    try {

        $ver = & $cmd --version 2>&1

        if ($ver -match "Python (\d+\.\d+\.\d+)") {

            if ([Version]$Matches[1] -ge $PythonMin) {

                $python = (Get-Command $cmd -ErrorAction Stop).Source

                Write-OK "Found $ver at $python"

                break
            }
        }
    }
    catch {}
}

if (-not $python) {

    Write-Host "`n   Python $PythonMin+ not found." -ForegroundColor Yellow
    Write-Host "   Download from: https://www.python.org/downloads/"
    Write-Host "   Check 'Add Python to PATH' during installation, then re-run this script."

    exit 1
}

$pythonw = Join-Path (Split-Path $python) "pythonw.exe"

if (-not (Test-Path $pythonw)) {
    $pythonw = $python
}

# ── 2. Create folders ─────────────────────────────────────────────────────────

Write-Step "Preparing directories..."

New-Item -ItemType Directory -Force -Path $WidgetDir | Out-Null
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

Write-OK "Directories ready"

# ── 3. Download / copy files ─────────────────────────────────────────────────

Write-Step "Installing widget files..."

$widgetContent  = Get-TextFile "widget.py"
$captureContent = Get-TextFile "rate_limit_capture.py"
$reqsContent    = Get-TextFile "requirements.txt"

[IO.File]::WriteAllText(
    "$WidgetDir\widget.py",
    $widgetContent,
    [Text.Encoding]::UTF8
)

[IO.File]::WriteAllText(
    "$ClaudeDir\rate_limit_capture.py",
    $captureContent,
    [Text.Encoding]::UTF8
)

[IO.File]::WriteAllText(
    "$WidgetDir\requirements.txt",
    $reqsContent,
    [Text.Encoding]::UTF8
)

Write-OK "widget.py installed"
Write-OK "rate_limit_capture.py installed"
Write-OK "requirements.txt installed"

# ── 4. Install dependencies ──────────────────────────────────────────────────

Write-Step "Installing dependencies..."

& $python -m pip install -r "$WidgetDir\requirements.txt"

if ($LASTEXITCODE -ne 0) {
    Fail "pip install failed — check internet connection"
}

Write-OK "Dependencies installed"

# ── 5. Configure Claude Code status line ─────────────────────────────────────

Write-Step "Configuring Claude Code..."

$captureScript = "$ClaudeDir\rate_limit_capture.py"

$cmdLine = "`"$python`" `"$captureScript`""

$settingsPath = "$ClaudeDir\settings.json"

$statusLineObject = @{
    type    = "command"
    command = $cmdLine
}

if (Test-Path $settingsPath) {

    try {

        $cfg = Get-Content $settingsPath -Raw -Encoding utf8 | ConvertFrom-Json
    }
    catch {

        Fail "~/.claude/settings.json is not valid JSON"
    }

    if (-not $cfg.statusLine) {

        $cfg | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $statusLineObject

        $cfg | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8

        Write-OK "statusLine added"
    }
    else {

        Write-OK "statusLine already exists"
    }
}
else {

    $cfg = @{
        statusLine = $statusLineObject
    }

    $cfg | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8

    Write-OK "settings.json created"
}

# ── 6. Kill old widget ───────────────────────────────────────────────────────

Write-Step "Stopping old widget instances..."

try {

    Get-CimInstance Win32_Process |
        Where-Object {
            $_.CommandLine -match "widget\.py"
        } |
        ForEach-Object {

            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}
catch {}

Start-Sleep -Milliseconds 500

Write-OK "Old widgets stopped"

# ── 7. Start widget ──────────────────────────────────────────────────────────

Write-Step "Launching widget..."

Start-Process `
    -FilePath $pythonw `
    -ArgumentList "`"$WidgetDir\widget.py`"" `
    -WindowStyle Hidden

Write-OK "Widget launched"

# ── 8. Auto-start at login ───────────────────────────────────────────────────

Write-Step "Configuring auto-start..."

$StartupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

$ShortcutPath = Join-Path $StartupDir "ClaudeUsageWidget.lnk"

$WScriptShell = New-Object -ComObject WScript.Shell

$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)

$Shortcut.TargetPath = $pythonw
$Shortcut.Arguments  = "`"$WidgetDir\widget.py`""
$Shortcut.WorkingDirectory = $WidgetDir

$Shortcut.Save()

Write-OK "Auto-start configured"

# ── Done ─────────────────────────────────────────────────────────────────────

Write-Host "`nDone!" -ForegroundColor Green

Write-Host "Claude Usage Widget is now installed and running." -ForegroundColor Gray

Write-Host "It will auto-start automatically at Windows login." -ForegroundColor Gray

Write-Host "Usage % appears after your first Claude Code API request." -ForegroundColor Gray
