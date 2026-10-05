"""The pipeline: find → intro email → follow-up → read replies → sample site / quote → hand off to you."""
import json
import logging
from datetime import datetime, timedelta, timezone

from . import ai, db, finder, mailer, notify, pricing
from .config import settings

log = logging.getLogger(__name__)


def is_paused() -> bool:
    return db.get_kv("paused", "0") == "1"


# ---------------------------------------------------------------- 1. find
def find_businesses(category: str, city: str, limit: int = 20, target: str = "weak_or_none") -> dict:
    """target: no_website | weak_or_none | all"""
    found = finder.search(category, city, limit)
    added = skipped = 0
    for biz in found:
        email = biz.pop("email", "")
        if biz["place_id"].startswith("demo-"):
            issues = ["No HTTPS (browsers show 'Not secure')", "Not mobile-friendly",
                      "No online booking or ordering"] if biz["website"] else ["No website"]
        else:
            issues, site_email = finder.audit_website(biz["website"])
            email = email or site_email
        has_site = bool(biz["website"]) and "Website is down or unreachable" not in issues

        if target == "no_website" and has_site:
            skipped += 1
            continue
        if target == "weak_or_none" and has_site and len(issues) < 2:
            skipped += 1
            continue

        revenue = pricing.estimate_revenue(biz["category"], biz["reviews"] or 0, biz["price_level"])
        lead_id = db.insert_lead({
            **biz, "email": email, "website_issues": "; ".join(issues),
            "est_revenue": revenue, "tier": pricing.tier_for(revenue),
            "needs": ",".join(pricing.recommend_services(has_site, issues)),
            "status": "new" if email else "needs_email",
        })
        if lead_id:
            added += 1
        else:
            skipped += 1
    return {"found": len(found), "added": added, "skipped": skipped}


def lead_quote(lead) -> dict:
    return pricing.quote(lead["tier"], [s for s in (lead["needs"] or "").split(",") if s])


# ---------------------------------------------------------------- 2. outreach
def send_intros(max_count: int | None = None) -> int:
    room = settings.daily_send_limit - db.cold_emails_sent_today()
    if max_count is not None:
        room = min(room, max_count)
    sent = 0
    for lead in db.list_leads("new"):
        if sent >= room:
            break
        if not lead["email"] or not lead["autopilot"]:
            continue
        mail = ai.intro_email(lead)
        _send(lead, mail["subject"], mail["body"], kind="intro")
        db.update_lead(lead["id"], status="contacted", last_contact_at=db.now())
        sent += 1
    return sent


def send_followups() -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(days=settings.followup_days)
    room = settings.daily_send_limit - db.cold_emails_sent_today()
    sent = 0
    for lead in db.list_leads("contacted"):
        if sent >= room:
            break
        if (not lead["autopilot"] or lead["followups"] >= settings.max_followups
                or not lead["last_contact_at"] or datetime.fromisoformat(lead["last_contact_at"]) > cutoff):
            continue
        mail = ai.followup_email(lead)
        last = db.last_outgoing(lead["id"])
        _send(lead, mail["subject"], mail["body"], kind="followup", in_reply_to=last["message_id"] if last else None)
        db.update_lead(lead["id"], followups=lead["followups"] + 1, last_contact_at=db.now())
        sent += 1
    return sent


def _send(lead, subject: str, body: str, *, kind: str, sender: str = "ai", in_reply_to: str | None = None) -> str:
    message_id, status = mailer.send(lead["email"], subject, body, token=lead["token"], in_reply_to=in_reply_to)
    db.add_message(lead["id"], direction="out", sender=sender, kind=kind, subject=subject, body=body,
                   message_id=message_id, in_reply_to=in_reply_to, status=status)
    if status == "failed":
        notify.alert(lead, "urgent", f"Email to {lead['email']} failed to send. Check SMTP settings.")
    return status


def send_manual(lead_id: int, body: str, subject: str | None = None) -> str:
    """You writing to the lead yourself from the dashboard."""
    lead = db.get_lead(lead_id)
    last = db.last_outgoing(lead_id)
    subject = subject or (f"Re: {last['subject']}" if last and not last["subject"].startswith("Re:")
                          else (last["subject"] if last else f"{settings.company_name} x {lead['name']}"))
    last_in = _last_inbound(lead_id)
    status = _send(lead, subject, body, kind="manual", sender="you",
                   in_reply_to=(last_in or last)["message_id"] if (last_in or last) else None)
    db.update_lead(lead_id, last_contact_at=db.now(),
                   status="contacted" if lead["status"] in ("new", "needs_email") else lead["status"])
    return status


def _last_inbound(lead_id: int):
    msgs = [m for m in db.thread(lead_id) if m["direction"] == "in"]
    return msgs[-1] if msgs else None


# ---------------------------------------------------------------- 3. replies
def check_replies() -> int:
    handled = 0
    for mail in mailer.fetch_replies():
        lead = None
        if mail["in_reply_to"]:
            original = db.find_message(mail["in_reply_to"].strip())
            if original:
                lead = db.get_lead(original["lead_id"])
        lead = lead or db.get_lead_by_email(mail["from"])
        if not lead:
            continue  # not a reply to our outreach
        handle_inbound(lead["id"], mail["body"], subject=mail["subject"], message_id=mail["message_id"])
        handled += 1
    return handled


def handle_inbound(lead_id: int, body: str, subject: str = "", message_id: str = "") -> dict:
    """Process one message from a lead. Also used by the dashboard's 'simulate reply' button."""
    lead = db.get_lead(lead_id)
    db.add_message(lead_id, direction="in", sender="lead", kind="inbound", subject=subject, body=body,
                   message_id=message_id or None, status="received")
    if lead["status"] in ("new", "contacted", "needs_email"):
        db.update_lead(lead_id, status="replied")

    result = ai.classify_reply(lead, body)
    intent = result["intent"]
    if result["services_wanted"]:
        needs = list(dict.fromkeys(result["services_wanted"] + (lead["needs"] or "").split(",")))
        db.update_lead(lead_id, needs=",".join(n for n in needs if n))
    lead = db.get_lead(lead_id)
    summary = f"Reply ({intent}): {result['summary']}"

    if intent == "unsubscribe":
        db.update_lead(lead_id, status="unsubscribed", autopilot=0)
        notify.alert(lead, "info", "Asked to stop emailing. Marked unsubscribed.")
        return result
    if intent == "out_of_office":
        notify.alert(lead, "info", "Auto-reply / out of office. Follow-up will still go out.")
        return result

    # You've taken over this lead: don't let the AI answer, just tell you.
    if not lead["autopilot"] or is_paused():
        notify.alert(lead, "urgent", f"New message (you're in control). {summary}")
        return result

    reply_subject = subject if subject.lower().startswith("re:") else f"Re: {subject or 'your website'}"
    history = [dict(m) for m in db.thread(lead_id)]
    quote = lead_quote(lead)

    if intent == "interested":
        if not lead["sample_html"]:
            db.update_lead(lead_id, sample_html=ai.sample_website(lead))
        link = f"{settings.public_base_url}/s/{lead['token']}"
        text = ai.write_reply(lead, history, quote=quote, goal=(
            f"Thank them warmly and share the free sample homepage we made for them: {link} . "
            "Ask what they think and what they'd like changed (photos, colors, services). "
            "Mention briefly that the full site comes with mobile design, hosting and an AI chatbot option, "
            f"and that the quote is here: {settings.public_base_url}/quote/{lead['token']} ."),
            fallback=(f"Thanks so much for getting back to me! I put together a free sample homepage for "
                      f"{lead['name']}: {link}\n\nTake a look and let me know what you think. Photos, colors and "
                      f"services can all be changed. Here's the pricing for the full package: "
                      f"{settings.public_base_url}/quote/{lead['token']}"))
        _send(lead, reply_subject, text, kind="reply", in_reply_to=message_id or None)
        db.update_lead(lead_id, status="sample_sent", last_contact_at=db.now())
        notify.alert(lead, "hot", f"Interested! Sample site sent: {link}\n{summary}")

    elif intent in ("ready_to_buy", "wants_call"):
        goal = (f"They want to move forward. Thank them, share the quote page "
                f"({settings.public_base_url}/quote/{lead['token']}), and say {settings.owner_name} will "
                "personally reach out within one business day to finalize details and payment."
                if intent == "ready_to_buy" else
                f"They'd like to talk. Say {settings.owner_name} will call them, and ask for the best number "
                "and a couple of times that work this week.")
        fallback = (f"That's great to hear! Here's your quote: {settings.public_base_url}/quote/{lead['token']}"
                    f"\n\nI'll reach out personally within one business day to go over the details."
                    if intent == "ready_to_buy" else
                    "Happy to talk! What's the best number to reach you, and what times work this week?")
        _send(lead, reply_subject, ai.write_reply(lead, history, goal=goal, quote=quote, fallback=fallback),
              kind="reply", in_reply_to=message_id or None)
        db.update_lead(lead_id, status="negotiating", last_contact_at=db.now())
        notify.alert(lead, "urgent", f"POTENTIAL DEAL. {summary}\nPhone: {lead['phone'] or 'n/a'}")

    elif intent == "not_interested":
        text = ai.write_reply(lead, history, goal=(
            "Politely thank them, no pressure, and say the offer stands if they ever change their mind. "
            "Two or three sentences."), fallback=(
            "No problem at all, thanks for letting me know. If you ever want a hand with your website "
            "down the road, I'm here."))
        _send(lead, reply_subject, text, kind="reply", in_reply_to=message_id or None)
        db.update_lead(lead_id, status="lost", autopilot=0)
        notify.alert(lead, "info", summary)

    else:  # question / other
        text = ai.write_reply(lead, history, quote=quote, goal=(
            "Answer their message helpfully and honestly. If they haven't seen a sample yet, offer to make "
            "a free sample homepage. End with a simple next step."),
            fallback=f"Thanks for your message! {settings.owner_name} will get back to you personally shortly.")
        _send(lead, reply_subject, text, kind="reply", in_reply_to=message_id or None)
        db.update_lead(lead_id, last_contact_at=db.now())
        notify.alert(lead, "hot" if result["is_potential_deal"] else "info", summary)
    return result


# ---------------------------------------------------------------- full cycle
def run_cycle() -> dict:
    if is_paused():
        return {"paused": True}
    out = {"replies": check_replies(), "followups": send_followups(), "intros": send_intros()}
    db.set_kv("last_cycle", json.dumps({"at": db.now(), **out}))
    return out
