"""Find local businesses (Google Places API) and check whether their website is missing or weak."""
import random
import re

import httpx

from .config import settings

PLACES_URL = "https://places.googleapis.com/v1/places:searchText"
FIELDS = ",".join([
    "places.id", "places.displayName", "places.formattedAddress", "places.nationalPhoneNumber",
    "places.websiteUri", "places.rating", "places.userRatingCount", "places.primaryTypeDisplayName",
    "places.priceLevel", "places.googleMapsUri", "nextPageToken",
])
PRICE_LEVELS = {
    "PRICE_LEVEL_INEXPENSIVE": 1, "PRICE_LEVEL_MODERATE": 2,
    "PRICE_LEVEL_EXPENSIVE": 3, "PRICE_LEVEL_VERY_EXPENSIVE": 4,
}
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
IGNORED_EMAIL_PARTS = ("example.", "sentry", "wixpress", ".png", ".jpg", "godaddy", "domain.com")


def search(category: str, city: str, limit: int = 20) -> list[dict]:
    """Return businesses matching e.g. category='plumber', city='Austin, TX'."""
    if settings.demo_mode:
        return _demo_businesses(category, city, limit)

    results, page_token = [], None
    while len(results) < limit:
        body = {"textQuery": f"{category} in {city}", "pageSize": min(20, limit - len(results))}
        if page_token:
            body["pageToken"] = page_token
        resp = httpx.post(PLACES_URL, json=body, timeout=30, headers={
            "X-Goog-Api-Key": settings.google_places_api_key, "X-Goog-FieldMask": FIELDS,
        })
        resp.raise_for_status()
        data = resp.json()
        for p in data.get("places", []):
            results.append({
                "place_id": p["id"],
                "name": p.get("displayName", {}).get("text", "Unknown"),
                "category": p.get("primaryTypeDisplayName", {}).get("text", category),
                "address": p.get("formattedAddress", ""),
                "city": city,
                "phone": p.get("nationalPhoneNumber", ""),
                "website": p.get("websiteUri", ""),
                "rating": p.get("rating"),
                "reviews": p.get("userRatingCount", 0),
                "price_level": PRICE_LEVELS.get(p.get("priceLevel", ""), None),
                "maps_url": p.get("googleMapsUri", ""),
            })
        page_token = data.get("nextPageToken")
        if not page_token:
            break
    return results[:limit]


def audit_website(url: str) -> tuple[list[str], str]:
    """Check a business website for problems we can sell a fix for. Returns (issues, email_found)."""
    if not url:
        return ["No website"], ""
    issues, email = [], ""
    try:
        resp = httpx.get(url, timeout=15, follow_redirects=True,
                         headers={"User-Agent": "Mozilla/5.0 (compatible; site-check)"})
        html = resp.text
        final_url = str(resp.url)
    except httpx.HTTPError:
        return ["Website is down or unreachable"], ""

    lower = html.lower()
    if not final_url.startswith("https://"):
        issues.append("No HTTPS (browsers show 'Not secure')")
    if 'name="viewport"' not in lower and "name='viewport'" not in lower:
        issues.append("Not mobile-friendly")
    if len(html) < 3000:
        issues.append("Very thin page / placeholder site")
    if any(b in lower for b in ("wix.com", "godaddysites", "weebly")) and "©" in html and "2019" in html:
        issues.append("Outdated site builder template")
    if not any(w in lower for w in ("book", "appointment", "schedule", "reserve", "order online")):
        issues.append("No online booking or ordering")
    if "chat" not in lower:
        issues.append("No chat / instant answers for visitors")

    email = _find_email(html)
    if not email:
        for path in ("/contact", "/contact-us", "/about"):
            try:
                email = _find_email(httpx.get(final_url.rstrip("/") + path, timeout=10, follow_redirects=True).text)
            except httpx.HTTPError:
                continue
            if email:
                break
    return issues, email


def _find_email(html: str) -> str:
    mailto = re.findall(r"mailto:([^\"'?>\s]+)", html)
    for candidate in mailto + EMAIL_RE.findall(html):
        if not any(part in candidate.lower() for part in IGNORED_EMAIL_PARTS):
            return candidate.strip()
    return ""


# ---------------------------------------------------------------- demo data
_DEMO_NAMES = {
    "default": ["Main Street {c}", "{city} {c} Co.", "Family {c} Services", "Elite {c}", "Sunrise {c}",
                "Hometown {c}", "Precision {c}", "Golden {c}", "Neighborhood {c}", "Summit {c}"],
}


def _demo_businesses(category: str, city: str, limit: int) -> list[dict]:
    """Fake but realistic businesses so the whole pipeline can be tested with no API keys."""
    rng = random.Random(f"{category}|{city}")
    c = category.title().rstrip("s")
    town = city.split(",")[0]
    out = []
    for i, pattern in enumerate(_DEMO_NAMES["default"][:limit]):
        name = pattern.format(c=c, city=town)
        slug = re.sub(r"[^a-z0-9]", "", name.lower())
        has_site = rng.random() < 0.3
        out.append({
            "place_id": f"demo-{slug}-{town.lower()}",
            "name": name,
            "category": category,
            "address": f"{rng.randint(100, 9999)} {rng.choice(['Oak', 'Main', 'Elm', 'Cedar', 'Park'])} St, {city}",
            "city": city,
            "phone": f"(555) {rng.randint(200, 999)}-{rng.randint(1000, 9999)}",
            "website": f"http://www.{slug}.example" if has_site else "",
            "rating": round(rng.uniform(3.6, 4.9), 1),
            "reviews": rng.choice([4, 12, 27, 48, 85, 140, 260, 610]),
            "price_level": rng.choice([None, 1, 2, 2, 3]),
            "maps_url": "",
            # demo leads get a fake inbox so the email flow can be exercised in dry-run mode
            "email": f"owner@{slug}.example",
        })
    return out
