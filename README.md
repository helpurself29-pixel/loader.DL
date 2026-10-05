# BizBot: AI outreach for local businesses

Finds local businesses with no website (or a weak one), estimates their size, emails them an intro, and
handles replies with AI. When someone's interested it builds a free sample homepage and a tailored quote, then
alerts you on potential deals. You can take over any conversation at any time.

```
Find businesses ─► Intro email ─► Follow-up ─► Reply arrives ─► AI reads it
                                                                 ├─ interested  → builds sample site + quote, replies, 🔥 alerts you
                                                                 ├─ ready / call → replies, 🚨 alerts you to close the deal
                                                                 ├─ question     → AI answers (or you, if you took over)
                                                                 ├─ not interested → polite close
                                                                 └─ stop         → unsubscribed, never emailed again
```

## Try it in 2 minutes (no accounts needed)

```bash
pip install -r requirements.txt
cp .env.example .env
uvicorn bizbot.app:app --reload
```

Open http://localhost:8000 (any username, password `change-me`). With no keys set it runs in **demo mode**
(sample businesses) and **dry-run** (emails are shown in the dashboard, never sent). Try it:

1. **Find businesses**: e.g. `plumber` in `Austin, TX`.
2. **Send intro emails**: read what would have gone out on each lead's page.
3. On a lead's page, **Simulate a reply** like *"Yes, show me a sample! How much?"* and watch it build the
   sample site, the quote and the alert.

## Going live

| What | Where | Cost |
|---|---|---|
| Claude API key (`ANTHROPIC_API_KEY`) | console.anthropic.com | roughly $0.02–0.10 per lead (more for sample sites) |
| Google Places key (`GOOGLE_PLACES_API_KEY`) | Google Cloud console → enable "Places API (New)" | free monthly credit covers light use |
| Outreach inbox (SMTP + IMAP) | Google Workspace or Zoho on a **separate domain** | ~$6–12/mo + ~$12/yr domain |
| Hosting (so sample-site links work) | Railway, Render or a $5 VPS, with a persistent disk for `bizbot.db` | ~$5–10/mo |
| Phone alerts (optional) | ntfy app → `NTFY_TOPIC` | free |

Then in `.env`: set `PUBLIC_BASE_URL` to your deployed URL, `COMPANY_ADDRESS`, a strong `DASHBOARD_PASSWORD`,
`DRY_RUN=false`, and `AUTOPILOT=true` to run the full cycle every `CYCLE_MINUTES`.

## Taking over a conversation

On any lead's page, click **✋ Take over**. The AI stops replying to that lead, and each new message from
them triggers an alert. Write to them from the same page (or have the AI draft something for you to edit).
**Hand back to AI** when you're done. **⏸ Pause all AI** on the dashboard stops everything at once.

## Pricing

`bizbot/pricing.py` holds the service list and prices. Each lead gets a rough yearly revenue estimate from
its category, Google review count and price level. That puts it in a tier (starter ×0.7, growth ×1.0,
premium ×1.6) which scales the quote. Edit the numbers to fit your market; you can also change the tier
and services per lead in the dashboard.

## Rules that keep you out of trouble

- **Cold email law (US CAN-SPAM):** emails must be honest, include your physical address and a working
  opt-out. BizBot adds the footer and unsubscribe link and honors "stop" replies automatically.
  Other countries are stricter (Canada's CASL, the EU's GDPR). Only target US businesses unless you've
  checked the local rules.
- **Protect your main email:** send from a separate domain, warm it up (start ~10/day and increase
  slowly), and keep `DAILY_SEND_LIMIT` modest. Mass blasting gets domains blacklisted.
- **Contact info:** businesses with no website often have no public email. Those land in `needs_email`
  with their phone number, so you can call them or add an email by hand. Targeting weak websites finds
  more emails.
