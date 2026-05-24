"""Track user activity for idle auto-stop on EC2."""

from __future__ import annotations

import os
import time
from pathlib import Path

_STACK_DIR = Path(os.environ.get("VOICE_STACK_STATE_DIR", Path.home() / ".voice-stack"))
ACTIVITY_FILE = Path(os.environ.get("ACTIVITY_FILE", _STACK_DIR / "last_activity"))
BOOT_FILE = Path(os.environ.get("BOOT_FILE", _STACK_DIR / "boot_time"))


def _write_ts(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(str(time.time()))


def touch_activity() -> None:
    """Record user interaction (WebSocket, clone, text, etc.)."""
    _write_ts(ACTIVITY_FILE)


def mark_boot() -> None:
    """Record stack boot time (grace period before idle stop)."""
    _write_ts(BOOT_FILE)
    _write_ts(ACTIVITY_FILE)


def last_activity_ts() -> float | None:
    if not ACTIVITY_FILE.is_file():
        return None
    try:
        return float(ACTIVITY_FILE.read_text().strip())
    except ValueError:
        return None


def boot_ts() -> float | None:
    if not BOOT_FILE.is_file():
        return None
    try:
        return float(BOOT_FILE.read_text().strip())
    except ValueError:
        return None
