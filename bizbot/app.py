"""Web dashboard + public pages. Run with:  uvicorn bizbot.app:app --reload"""
import json
import logging
import secrets
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from fastapi.templating import Jinja2Templates

from . import ai, db, engine, pricing, sites
from .config import settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("bizbot")
templates = Jinja2Templates(directory=Path(__file__).parent / "templates")
security = HTTPBasic()


def _scheduler():
    while True:
        try:
            log.info("autopilot cycle: %s", engine.run_cycle())
        except Exception:
            log.exception("autopilot cycle failed")
        time.sleep(settings.cycle_minutes * 60)


@asynccontextmanager
async def lifespan(_app):
    db.init()
    if settings.autopilot:
        threading.Thread(target=_scheduler, daemon=True).start()
    yield


app = FastAPI(title="BizBot", lifespan=lifespan)


def auth(creds: HTTPBasicCredentials = Depends(security)):
    if not secrets.compare_digest(creds.password.encode(), settings.dashboard_password.encode()):
        raise HTTPException(401, headers={"WWW-Authenticate": "Basic"})


def back(url: str = "/"):
    return RedirectResponse(url, status_code=303)


# ---------------------------------------------------------------- dashboard
@app.get("/", response_class=HTMLResponse, dependencies=[Depends(auth)])
def dashboard(request: Request, status: str | None = None):
    last = db.get_kv("last_cycle")
    return templates.TemplateResponse(request, "dashboard.html", {
        "settings": settings, "ai_on": ai.enabled(), "counts": db.status_counts(), "statuses": db.STATUSES,
        "leads": db.list_leads(status), "filter": status, "events": db.recent_events(),
        "paused": engine.is_paused(), "sent_today": db.cold_emails_sent_today(),
        "last_cycle": json.loads(last) if last else None,
    })


@app.post("/actions/find", dependencies=[Depends(auth)])
def action_find(category: str = Form(...), city: str = Form(...), limit: int = Form(20),
                target: str = Form("weak_or_none")):
    engine.find_businesses(category.strip(), city.strip(), min(limit, 60), target)
    return back()


@app.post("/actions/{name}", dependencies=[Depends(auth)])
def action(name: str):
    if name == "intros":
        n = engine.send_intros()
        db.add_event(None, "info", f"Sent {n} intro emails" + (" (dry run)" if settings.dry_run else ""))
    elif name == "followups":
        db.add_event(None, "info", f"Sent {engine.send_followups()} follow-ups")
    elif name == "replies":
        db.add_event(None, "info", f"Processed {engine.check_replies()} new replies")
    elif name == "cycle":
        db.add_event(None, "info", f"Cycle: {engine.run_cycle()}")
    elif name == "pause":
        db.set_kv("paused", "0" if engine.is_paused() else "1")
    elif name == "seen":
        with db.tx() as c:
            c.execute("UPDATE events SET seen = 1")
    else:
        raise HTTPException(404)
    return back()


# ---------------------------------------------------------------- one lead
@app.get("/leads/{lead_id}", response_class=HTMLResponse, dependencies=[Depends(auth)])
def lead_page(request: Request, lead_id: int):
    lead = db.get_lead(lead_id) or _404()
    return templates.TemplateResponse(request, "lead.html", {
        "settings": settings, "lead": lead, "thread": db.thread(lead_id), "quote": engine.lead_quote(lead),
        "statuses": db.STATUSES, "services": pricing.SERVICES, "tiers": list(pricing.TIERS),
    })


@app.post("/leads/{lead_id}/takeover", dependencies=[Depends(auth)])
def takeover(lead_id: int):
    db.update_lead(lead_id, autopilot=0)
    db.add_event(lead_id, "info", "You took over this conversation. AI will not reply.")
    return back(f"/leads/{lead_id}")


@app.post("/leads/{lead_id}/handback", dependencies=[Depends(auth)])
def handback(lead_id: int):
    db.update_lead(lead_id, autopilot=1)
    db.add_event(lead_id, "info", "Handed back to the AI.")
    return back(f"/leads/{lead_id}")


@app.post("/leads/{lead_id}/send", dependencies=[Depends(auth)])
def send(lead_id: int, body: str = Form(...), subject: str = Form("")):
    lead = db.get_lead(lead_id) or _404()
    if not lead["email"]:
        raise HTTPException(400, "Add an email address for this lead first.")
    engine.send_manual(lead_id, body.strip(), subject.strip() or None)
    return back(f"/leads/{lead_id}")


@app.post("/leads/{lead_id}/draft", response_class=HTMLResponse, dependencies=[Depends(auth)])
def draft(request: Request, lead_id: int, goal: str = Form("Reply helpfully to their last message.")):
    """Let the AI draft a reply that you can edit before sending yourself."""
    lead = db.get_lead(lead_id) or _404()
    text = ai.write_reply(lead, [dict(m) for m in db.thread(lead_id)], goal=goal, quote=engine.lead_quote(lead))
    return templates.TemplateResponse(request, "lead.html", {
        "settings": settings, "lead": lead, "thread": db.thread(lead_id), "quote": engine.lead_quote(lead),
        "statuses": db.STATUSES, "services": pricing.SERVICES, "tiers": list(pricing.TIERS), "draft": text,
    })


@app.post("/leads/{lead_id}/simulate", dependencies=[Depends(auth)])
def simulate(lead_id: int, body: str = Form(...)):
    """Pretend the lead replied: lets you test the whole flow in dry-run mode."""
    db.get_lead(lead_id) or _404()
    engine.handle_inbound(lead_id, body.strip(), subject="Re: (simulated)")
    return back(f"/leads/{lead_id}")


@app.post("/leads/{lead_id}/sample", dependencies=[Depends(auth)])
def regenerate_sample(lead_id: int):
    lead = db.get_lead(lead_id) or _404()
    db.update_lead(lead_id, sample_html=ai.sample_website(lead))
    return back(f"/leads/{lead_id}")


@app.post("/leads/{lead_id}/update", dependencies=[Depends(auth)])
def update(lead_id: int, email: str = Form(""), status: str = Form(...), tier: str = Form(...),
           notes: str = Form("")):
    lead = db.get_lead(lead_id) or _404()
    fields = {"email": email.strip(), "status": status, "tier": tier, "notes": notes}
    if lead["status"] == "needs_email" and email.strip() and status == "needs_email":
        fields["status"] = "new"
    db.update_lead(lead_id, **fields)
    return back(f"/leads/{lead_id}")


@app.post("/leads/{lead_id}/services", dependencies=[Depends(auth)])
async def update_services(lead_id: int, request: Request):
    form = await request.form()
    db.update_lead(lead_id, needs=",".join(k for k in form.getlist("needs") if k in pricing.SERVICES))
    return back(f"/leads/{lead_id}")


# ---------------------------------------------------------------- public pages
@app.get("/s/{token}", response_class=HTMLResponse)
def sample_site(token: str):
    lead = db.get_lead_by_token(token)
    if not lead or not lead["sample_html"]:
        _404()
    return HTMLResponse(lead["sample_html"])


@app.get("/quote/{token}", response_class=HTMLResponse)
def quote_page(request: Request, token: str):
    lead = db.get_lead_by_token(token) or _404()
    return templates.TemplateResponse(request, "quote.html", {
        "settings": settings, "lead": lead, "quote": engine.lead_quote(lead)})


@app.get("/showcase", response_class=HTMLResponse)
def showcase(request: Request):
    return templates.TemplateResponse(request, "showcase.html", {"settings": settings, "sites": sites.SHOWCASE})


@app.get("/showcase/{slug}", response_class=HTMLResponse)
def showcase_site(slug: str):
    demo = next((s for s in sites.SHOWCASE if s["slug"] == slug), None) or _404()
    return HTMLResponse(sites.render_template_site({**demo, "address": demo["city"]}, banner=False))


@app.get("/unsubscribe/{token}", response_class=HTMLResponse)
def unsubscribe(request: Request, token: str):
    lead = db.get_lead_by_token(token)
    if lead and lead["status"] != "unsubscribed":
        db.update_lead(lead["id"], status="unsubscribed", autopilot=0)
        db.add_event(lead["id"], "info", "Unsubscribed via link.")
    return templates.TemplateResponse(request, "message.html", {
        "settings": settings, "title": "You're unsubscribed",
        "text": f"You won't receive any more emails from {settings.company_name}. Sorry for the bother!"})


def _404():
    raise HTTPException(404)
