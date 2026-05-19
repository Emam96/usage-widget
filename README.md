# Claude Code Usage Widget

A Windows system tray tool that shows your Claude Code token usage in real time.

![icon colors: green < 50%, yellow 50–80%, red > 80%]

## What it shows

Hover over the tray icon to see:

```
Claude Code
5h: 15% used
Reset in: 3h 41m
Today: 600,249 tokens
```

The percentage and reset time match exactly what Claude.ai shows on the Plan usage page. The icon turns green → yellow → red as usage climbs.

## Requirements

- Windows 10/11
- Python 3.8+ ([download](https://www.python.org/downloads/)) — check "Add Python to PATH"
- Claude Code installed with a **Pro or Max** subscription

## Install

```powershell
irm https://raw.githubusercontent.com/Emam96/usage-widget/main/install.ps1 | iex
```

Or clone and run locally:

```powershell
git clone https://github.com/Emam96/usage-widget
cd usage-widget
.\install.ps1
```

That's it. The widget starts immediately and auto-launches at every login.

## How it works

Claude Code has a built-in **status line** feature that pipes rate-limit data (as JSON) to any script you configure after each API response. This widget taps into that to get the exact same utilization and reset timestamp that Claude.ai displays — no guessing, no token counting.

## Uninstall

1. Right-click the tray icon → **Quit**
2. Delete `%USERPROFILE%\ClaudeUsageWidget\`
3. Remove the `statusLine` entry from `%USERPROFILE%\.claude\settings.json`
4. Remove `ClaudeUsageWidget` from `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
