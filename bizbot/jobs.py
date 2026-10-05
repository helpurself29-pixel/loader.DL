"""Runs slow work (AI emails, sample sites) in the background so the dashboard never hangs.

One job at a time: AI calls take 10-60s each, and running jobs one by one keeps the order of
emails predictable and the SQLite database happy.
"""
import logging
import threading
import time

from . import db

log = logging.getLogger(__name__)
_lock = threading.Lock()
_current: dict = {}


def start(name: str, fn, *args, done_message=None, quiet_if_busy: bool = False) -> bool:
    """Start fn(*args) in the background. done_message(result) -> text for the alert feed."""
    if not _lock.acquire(blocking=False):
        if not quiet_if_busy:
            db.add_event(None, "info", f"Still busy with “{_current.get('name')}”. Try again when it finishes.")
        return False
    _current.update(name=name, started=time.time())

    def run():
        try:
            result = fn(*args)
            db.add_event(None, "info", done_message(result) if done_message else f"✓ {name} finished")
        except Exception as e:
            log.exception("job %s failed", name)
            db.add_event(None, "urgent", f"{name} failed: {e}")
        finally:
            _current.clear()
            _lock.release()

    threading.Thread(target=run, daemon=True, name=f"job:{name}").start()
    return True


def running() -> str | None:
    """Human-readable description of the job in progress, or None."""
    if not _current:
        return None
    return f"{_current['name']} (running {int(time.time() - _current['started'])}s)"
