# Claude Code Usage Widget — Installer
# Run this once. It sets up everything and auto-starts at every boot.

$ErrorActionPreference = "Stop"

$WidgetDir  = "$env:USERPROFILE\ClaudeUsageWidget"
$ClaudeDir  = "$env:USERPROFILE\.claude"
$PythonMin  = [Version]"3.8"

# If running from the cloned repo, use local files; otherwise download from GitHub
$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$GitHubBase   = "https://raw.githubusercontent.com/YOURUSERNAME/usage-widget/main"

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "   OK  $msg" -ForegroundColor Green }
function Fail($msg)       { Write-Host "`n   ERROR: $msg" -ForegroundColor Red; exit 1 }

function Get-TextFile($filename) {
    $local = Join-Path $ScriptDir $filename
    if (Test-Path $local) {
        return Get-Content $local -Raw -Encoding utf8
    }
    try {
        return (Invoke-WebRequest -Uri "$GitHubBase/$filename" -UseBasicParsing).Content
    } catch {
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
    } catch {}
}

if (-not $python) {
    Write-Host "`n   Python $PythonMin+ not found." -ForegroundColor Yellow
    Write-Host "   Download from: https://www.python.org/downloads/"
    Write-Host "   Check 'Add Python to PATH' during installation, then re-run this script."
    exit 1
}

$pythonw = Join-Path (Split-Path $python) "pythonw.exe"
if (-not (Test-Path $pythonw)) { $pythonw = $python }

# ── 2. Copy files ─────────────────────────────────────────────────────────────
Write-Step "Installing widget files..."

New-Item -ItemType Directory -Force -Path $WidgetDir | Out-Null
New-Item -ItemType Directory -Force -Path $ClaudeDir  | Out-Null

$widgetContent  = Get-TextFile "widget.py"
$captureContent = Get-TextFile "rate_limit_capture.py"
$reqsContent    = Get-TextFile "requirements.txt"

[IO.File]::WriteAllText("$WidgetDir\widget.py",             $widgetContent,  [Text.Encoding]::UTF8)
[IO.File]::WriteAllText("$ClaudeDir\rate_limit_capture.py", $captureContent, [Text.Encoding]::UTF8)
[IO.File]::WriteAllText("$WidgetDir\requirements.txt",      $reqsContent,    [Text.Encoding]::UTF8)

Write-OK "widget.py          → $WidgetDir\widget.py"
Write-OK "rate_limit_capture → $ClaudeDir\rate_limit_capture.py"

# ── 3. Install pip dependencies ───────────────────────────────────────────────
Write-Step "Installing dependencies (pystray, Pillow)..."

& $python -m pip install -r "$WidgetDir\requirements.txt" --quiet
if ($LASTEXITCODE -ne 0) { Fail "pip install failed — check your internet connection and try again." }
Write-OK "Dependencies installed"

# ── 4. Patch ~/.claude/settings.json ─────────────────────────────────────────
Write-Step "Configuring Claude Code status line..."

$captureScript = "$ClaudeDir\rate_limit_capture.py"
$cmdLine       = "`"$python`" `"$captureScript`""
$cmdJson       = $cmdLine | ConvertTo-Json   # handles backslash and quote escaping

$settingsPath = "$ClaudeDir\settings.json"

if (Test-Path $settingsPath) {
    $raw = Get-Content $settingsPath -Raw -Encoding utf8
    # Parse to check if statusLine already exists
    try { $cfg = $raw | ConvertFrom-Json } catch { Fail "~/.claude/settings.json is not valid JSON. Fix it manually then re-run." }

    if ($cfg.PSObject.Properties["statusLine"]) {
        Write-OK "statusLine already present in settings.json — skipped"
    } else {
        # Insert before the closing brace
        $patch  = $raw.TrimEnd().TrimEnd("}")
        $patch += ",`n  `"statusLine`": { `"type`": `"command`", `"command`": $cmdJson }`n}"
        [IO.File]::WriteAllText($settingsPath, $patch, [Text.Encoding]::UTF8)
        Write-OK "statusLine added to settings.json"
    }
} else {
    $newCfg = "{ `"statusLine`": { `"type`": `"command`", `"command`": $cmdJson } }"
    [IO.File]::WriteAllText($settingsPath, $newCfg, [Text.Encoding]::UTF8)
    Write-OK "Created settings.json with statusLine"
}

# ── 5. Kill old widget, launch new one ────────────────────────────────────────
Write-Step "Starting widget..."

try {
    Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -match "widget\.py" } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
} catch {}

Start-Sleep -Milliseconds 300
Start-Process -FilePath $pythonw -ArgumentList "`"$WidgetDir\widget.py`"" -WindowStyle Hidden
Write-OK "Widget launched"

Write-Host "`n  Done! The Claude Usage Widget is running in your system tray." -ForegroundColor Green
Write-Host "  It will auto-start at every login — no further setup needed." -ForegroundColor Gray
Write-Host "  The usage % appears after your first Claude Code API call (Pro/Max plans)." -ForegroundColor Gray
