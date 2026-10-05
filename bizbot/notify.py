"""Alerts to you: dashboard feed, email, and optional phone push (ntfy) or Discord."""
import logging

import httpx

from . import db, mailer
from .config import settings

log = logging.getLogger(__name__)


def alert(lead, level: str, text: str):
    """level: info (dashboard only) | hot (potential deal) | urgent (needs you now)."""
    db.add_event(lead["id"] if lead else None, level, text)
    if level == "info":
        return
    link = f"{settings.public_base_url}/leads/{lead['id']}" if lead else settings.public_base_url
    title = f"{'🔥' if level == 'hot' else '🚨'} {lead['name'] if lead else 'BizBot'}"
    body = f"{text}\n\nOpen the lead: {link}"

    mailer.send_plain(settings.owner_email, title, body)
    try:
        if settings.ntfy_topic:
            httpx.post(f"https://ntfy.sh/{settings.ntfy_topic}", content=body.encode(),
                       headers={"Title": title.encode("ascii", "ignore").decode() or "BizBot",
                                "Priority": "high" if level == "urgent" else "default", "Click": link},
                       timeout=10)
        if settings.discord_webhook_url:
            httpx.post(settings.discord_webhook_url, json={"content": f"**{title}**\n{body}"}, timeout=10)
    except httpx.HTTPError as e:
        log.warning("push notification failed: %s", e)
