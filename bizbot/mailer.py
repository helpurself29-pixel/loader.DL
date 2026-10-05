"""Send email over SMTP and read replies over IMAP. In dry-run mode nothing leaves the machine."""
import email
import imaplib
import logging
import re
import smtplib
from email.message import EmailMessage
from email.utils import make_msgid, parseaddr

from .config import settings

log = logging.getLogger(__name__)


def footer(token: str) -> str:
    """CAN-SPAM: identify the sender, give a physical address and a working opt-out."""
    addr = settings.company_address or "[set COMPANY_ADDRESS]"
    return (f"\n\n--\n{settings.company_name} · {addr}\n"
            f"Not interested? Reply STOP or unsubscribe: {settings.public_base_url}/unsubscribe/{token}")


def send(to: str, subject: str, body: str, *, token: str, in_reply_to: str | None = None) -> tuple[str, str]:
    """Returns (message_id, status) where status is sent | dry_run | failed."""
    domain = (settings.from_email.split("@")[-1] if settings.from_email else "localhost")
    message_id = make_msgid(domain=domain)
    if settings.dry_run:
        log.info("[dry run] would email %s: %s", to, subject)
        return message_id, "dry_run"

    msg = EmailMessage()
    msg["From"] = f"{settings.owner_name} at {settings.company_name} <{settings.from_email}>"
    msg["To"] = to
    msg["Subject"] = subject
    msg["Message-ID"] = message_id
    msg["List-Unsubscribe"] = f"<{settings.public_base_url}/unsubscribe/{token}>"
    if in_reply_to:
        msg["In-Reply-To"] = in_reply_to
        msg["References"] = in_reply_to
    msg.set_content(body + footer(token))
    try:
        _smtp_send(msg)
        return message_id, "sent"
    except (smtplib.SMTPException, OSError) as e:
        log.error("send to %s failed: %s", to, e)
        return message_id, "failed"


def send_plain(to: str, subject: str, body: str):
    """Internal notifications to you (no footer, ignores dry-run)."""
    if not (settings.smtp_host and to):
        return
    msg = EmailMessage()
    msg["From"] = settings.from_email
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(body)
    try:
        _smtp_send(msg)
    except (smtplib.SMTPException, OSError) as e:
        log.error("notification email failed: %s", e)


def _smtp_send(msg: EmailMessage):
    if settings.smtp_port == 465:
        server = smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, timeout=30)
    else:
        server = smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=30)
        server.starttls()
    with server:
        server.login(settings.smtp_user, settings.smtp_password)
        server.send_message(msg)


def fetch_replies() -> list[dict]:
    """Unread inbox messages: [{from, subject, body, message_id, in_reply_to}]. Marks them read."""
    if not settings.imap_host:
        return []
    out = []
    try:
        with imaplib.IMAP4_SSL(settings.imap_host, settings.imap_port) as box:
            box.login(settings.imap_user, settings.imap_password)
            box.select("INBOX")
            _, ids = box.search(None, "UNSEEN")
            for num in ids[0].split():
                _, data = box.fetch(num, "(RFC822)")
                msg = email.message_from_bytes(data[0][1])
                refs = (msg.get("References") or "").split()
                out.append({
                    "from": parseaddr(msg.get("From", ""))[1].lower(),
                    "subject": msg.get("Subject", ""),
                    "body": strip_quoted(_text_body(msg)),
                    "message_id": msg.get("Message-ID", ""),
                    "in_reply_to": msg.get("In-Reply-To") or (refs[-1] if refs else ""),
                })
                box.store(num, "+FLAGS", "\\Seen")
    except (imaplib.IMAP4.error, OSError) as e:
        log.error("IMAP check failed: %s", e)
    return out


def _text_body(msg) -> str:
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain" and "attachment" not in str(part.get("Content-Disposition")):
                return part.get_payload(decode=True).decode(part.get_content_charset() or "utf-8", "replace")
        for part in msg.walk():
            if part.get_content_type() == "text/html":
                html = part.get_payload(decode=True).decode(part.get_content_charset() or "utf-8", "replace")
                return re.sub(r"<[^>]+>", " ", html)
        return ""
    return msg.get_payload(decode=True).decode(msg.get_content_charset() or "utf-8", "replace")


def strip_quoted(text: str) -> str:
    """Keep only the new part of a reply (drop '> quoted' lines and 'On ... wrote:' history)."""
    lines = []
    for line in text.splitlines():
        if re.match(r"^\s*On .+wrote:\s*$", line) or line.strip().startswith("-----Original Message"):
            break
        if line.lstrip().startswith(">"):
            continue
        lines.append(line)
    return "\n".join(lines).strip()
