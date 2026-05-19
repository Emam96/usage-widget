import json
import sys
import time
from pathlib import Path

try:
    data = json.load(sys.stdin)
    rl = data.get("rate_limits", {})
    five = rl.get("five_hour", {})
    pct = five.get("used_percentage")
    resets_at = five.get("resets_at")
    result = {
        "pct": pct,
        "resets_at": resets_at,
        "captured_at": time.time(),
    }
    out = Path.home() / ".claude" / "rate_limit_status.json"
    out.write_text(json.dumps(result), encoding="utf-8")
    if pct is not None:
        print(f"5h: {pct:.0f}% used", end="")
except Exception:
    pass
