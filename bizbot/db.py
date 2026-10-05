"""SQLite storage for leads, the email conversation with each lead, and alerts."""
import secrets
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone

from .config import settings

SCHEMA = """
CREATE TABLE IF NOT EXISTS leads (
    id INTEGER PRIMARY KEY,
    place_id TEXT UNIQUE,
    name TEXT NOT NULL,
    category TEXT,
    address TEXT,
    city TEXT,
    phone TEXT,
    email TEXT,
    website TEXT,
    website_issues TEXT,
    rating REAL,
    reviews INTEGER DEFAULT 0,
    price_level INTEGER,
    maps_url TEXT,
    est_revenue INTEGER,
    tier TEXT,
    needs TEXT,
    status TEXT DEFAULT 'new',
    autopilot INTEGER DEFAULT 1,
    token TEXT UNIQUE,
    sample_html TEXT,
    followups INTEGER DEFAULT 0,
    notes TEXT,
    last_contact_at TEXT,
    created_at TEXT,
    updated_at TEXT
);
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY,
    lead_id INTEGER REFERENCES leads(id),
    direction TEXT,          -- out | in
    sender TEXT,             -- ai | you | lead
    kind TEXT,               -- intro | followup | reply | manual | inbound
    subject TEXT,
    body TEXT,
    message_id TEXT,
    in_reply_to TEXT,
    status TEXT,             -- sent | dry_run | failed | received
    created_at TEXT
);
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY,
    lead_id INTEGER,
    level TEXT,              -- info | hot | urgent
    text TEXT,
    seen INTEGER DEFAULT 0,
    created_at TEXT
);
CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT);
"""

# Pipeline statuses, in order
STATUSES = [
    "new", "needs_email", "contacted", "replied", "interested", "sample_sent",
    "negotiating", "won", "lost", "unsubscribed",
]


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def connect() -> sqlite3.Connection:
    conn = sqlite3.connect(settings.database_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


@contextmanager
def tx():
    conn = connect()
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init():
    with tx() as c:
        c.executescript(SCHEMA)


def insert_lead(data: dict) -> int | None:
    """Insert a lead; returns its id, or None if this business is already in the database."""
    data = {**data, "token": secrets.token_urlsafe(10), "created_at": now(), "updated_at": now()}
    cols = ", ".join(data)
    marks = ", ".join("?" for _ in data)
    with tx() as c:
        cur = c.execute(f"INSERT OR IGNORE INTO leads ({cols}) VALUES ({marks})", list(data.values()))
        return cur.lastrowid if cur.rowcount else None


def update_lead(lead_id: int, **fields):
    fields["updated_at"] = now()
    sets = ", ".join(f"{k} = ?" for k in fields)
    with tx() as c:
        c.execute(f"UPDATE leads SET {sets} WHERE id = ?", [*fields.values(), lead_id])


def get_lead(lead_id: int):
    with tx() as c:
        return c.execute("SELECT * FROM leads WHERE id = ?", (lead_id,)).fetchone()


def get_lead_by_token(token: str):
    with tx() as c:
        return c.execute("SELECT * FROM leads WHERE token = ?", (token,)).fetchone()


def get_lead_by_email(email: str):
    with tx() as c:
        return c.execute("SELECT * FROM leads WHERE lower(email) = lower(?)", (email,)).fetchone()


def list_leads(status: str | None = None):
    with tx() as c:
        if status:
            return c.execute("SELECT * FROM leads WHERE status = ? ORDER BY updated_at DESC", (status,)).fetchall()
        return c.execute("SELECT * FROM leads ORDER BY updated_at DESC").fetchall()


def status_counts() -> dict:
    with tx() as c:
        rows = c.execute("SELECT status, COUNT(*) n FROM leads GROUP BY status").fetchall()
    return {r["status"]: r["n"] for r in rows}


def add_message(lead_id: int, **fields) -> int:
    fields = {"lead_id": lead_id, "created_at": now(), **fields}
    cols = ", ".join(fields)
    marks = ", ".join("?" for _ in fields)
    with tx() as c:
        return c.execute(f"INSERT INTO messages ({cols}) VALUES ({marks})", list(fields.values())).lastrowid


def thread(lead_id: int):
    with tx() as c:
        return c.execute("SELECT * FROM messages WHERE lead_id = ? ORDER BY id", (lead_id,)).fetchall()


def find_message(message_id: str):
    with tx() as c:
        return c.execute("SELECT * FROM messages WHERE message_id = ?", (message_id,)).fetchone()


def last_outgoing(lead_id: int):
    with tx() as c:
        return c.execute(
            "SELECT * FROM messages WHERE lead_id = ? AND direction = 'out' ORDER BY id DESC LIMIT 1", (lead_id,)
        ).fetchone()


def cold_emails_sent_today() -> int:
    today = datetime.now(timezone.utc).date().isoformat()
    with tx() as c:
        return c.execute(
            "SELECT COUNT(*) FROM messages WHERE kind IN ('intro', 'followup') "
            "AND created_at >= ? AND status IN ('sent', 'dry_run')",
            (today,),
        ).fetchone()[0]


def add_event(lead_id: int | None, level: str, text: str):
    with tx() as c:
        c.execute("INSERT INTO events (lead_id, level, text, created_at) VALUES (?, ?, ?, ?)",
                  (lead_id, level, text, now()))


def recent_events(limit: int = 30):
    with tx() as c:
        return c.execute("SELECT * FROM events ORDER BY id DESC LIMIT ?", (limit,)).fetchall()


def get_kv(key: str, default: str | None = None) -> str | None:
    with tx() as c:
        row = c.execute("SELECT value FROM kv WHERE key = ?", (key,)).fetchone()
    return row["value"] if row else default


def set_kv(key: str, value: str):
    with tx() as c:
        c.execute("INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                  (key, value))
