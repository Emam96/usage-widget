import json
import sys
import time
import threading
import winreg
from datetime import datetime, timezone
from pathlib import Path

import pystray
from PIL import Image, ImageDraw

REFRESH_SECONDS = 30
WINDOW_SECONDS = 5 * 3600

CLAUDE_DIR = Path.home() / ".claude"
PROJECTS_DIR = CLAUDE_DIR / "projects"
STATUS_FILE = CLAUDE_DIR / "rate_limit_status.json"


def read_rate_limit_status() -> dict | None:
    """Read rate limit data captured by the status line script."""
    try:
        data = json.loads(STATUS_FILE.read_text(encoding="utf-8"))
        pct = data.get("pct")
        resets_at = data.get("resets_at")
        captured_at = data.get("captured_at", 0)
        if pct is None or resets_at is None:
            return None
        # Discard stale data older than 6 hours
        if time.time() - captured_at > 6 * 3600:
            return None
        reset_in = max(0.0, resets_at - time.time())
        return {"pct": float(pct), "reset_in_seconds": reset_in}
    except Exception:
        return None


def parse_today_tokens() -> tuple[int, int]:
    """Return (active_tokens, cache_tokens) for today from JSONL files."""
    today_midnight = (
        datetime.now(timezone.utc)
        .astimezone()
        .replace(hour=0, minute=0, second=0, microsecond=0)
        .timestamp()
    )
    active = 0
    cache = 0
    try:
        jsonl_files = list(PROJECTS_DIR.glob("**/*.jsonl"))
    except Exception:
        return active, cache

    for path in jsonl_files:
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except Exception:
            continue
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("type") != "assistant":
                continue
            msg = entry.get("message")
            if not isinstance(msg, dict):
                continue
            usage = msg.get("usage")
            if not usage:
                continue
            ts_str = entry.get("timestamp")
            if not ts_str:
                continue
            try:
                ts = datetime.fromisoformat(ts_str).timestamp()
            except ValueError:
                continue
            if ts < today_midnight:
                continue
            active += usage.get("input_tokens", 0) + usage.get("output_tokens", 0)
            cache += (
                usage.get("cache_creation_input_tokens", 0)
                + usage.get("cache_read_input_tokens", 0)
            )
    return active, cache


def build_tooltip(rl: dict | None, today_active: int) -> str:
    if rl is None:
        return (
            "Claude Code\n"
            "5h: ?? % (waiting for API call...)\n"
            "Reset in: —\n"
            "Today: {:,} tokens".format(today_active)
        )

    secs = int(rl["reset_in_seconds"])
    h, rem = divmod(secs, 3600)
    m = rem // 60

    return (
        "Claude Code\n"
        "5h: {:.0f}% used\n"
        "Reset in: {}h {:02d}m\n"
        "Today: {:,} tokens"
    ).format(rl["pct"], h, m, today_active)


def make_icon(pct: float | None) -> Image.Image:
    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    if pct is None:
        color = (150, 150, 150, 255)
    elif pct >= 80:
        color = (220, 50, 50, 255)
    elif pct >= 50:
        color = (220, 180, 0, 255)
    else:
        color = (50, 200, 80, 255)
    margin = 4
    draw.ellipse([margin, margin, size - margin, size - margin], fill=color)
    return img


def register_autostart() -> None:
    try:
        script_path = Path(__file__).resolve()
        pythonw = Path(sys.executable).parent / "pythonw.exe"
        if not pythonw.exists():
            pythonw = Path(sys.executable)
        cmd = f'"{pythonw}" "{script_path}"'
        key = winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Run",
            0,
            winreg.KEY_READ | winreg.KEY_SET_VALUE,
        )
        try:
            existing, _ = winreg.QueryValueEx(key, "ClaudeUsageWidget")
            if existing == cmd:
                winreg.CloseKey(key)
                return
        except FileNotFoundError:
            pass
        winreg.SetValueEx(key, "ClaudeUsageWidget", 0, winreg.REG_SZ, cmd)
        winreg.CloseKey(key)
    except Exception:
        pass


def main() -> None:
    register_autostart()

    rl = read_rate_limit_status()
    today_active, _ = parse_today_tokens()
    tooltip = build_tooltip(rl, today_active)
    icon_image = make_icon(rl["pct"] if rl else None)

    icon_ref: dict = {}

    def refresh_loop() -> None:
        while True:
            time.sleep(REFRESH_SECONDS)
            try:
                new_rl = read_rate_limit_status()
                new_today, _ = parse_today_tokens()
                new_tooltip = build_tooltip(new_rl, new_today)
                new_image = make_icon(new_rl["pct"] if new_rl else None)
                tray = icon_ref.get("icon")
                if tray is not None:
                    tray.title = new_tooltip
                    tray.icon = new_image
            except Exception:
                pass

    menu = pystray.Menu(pystray.MenuItem("Quit", lambda icon, item: icon.stop()))
    tray_icon = pystray.Icon("ClaudeUsageWidget", icon_image, tooltip, menu=menu)
    icon_ref["icon"] = tray_icon

    t = threading.Thread(target=refresh_loop, daemon=True)
    t.start()

    tray_icon.run()


if __name__ == "__main__":
    main()
