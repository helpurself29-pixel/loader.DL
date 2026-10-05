"""Rough income estimate per business, and service prices scaled to what they can afford.

The revenue numbers are ballpark heuristics (category average x popularity), not real financial data.
Their only job is to pick a sensible price tier. Edit SERVICES and CATEGORY_REVENUE to fit your market.
"""

# Base prices (the "growth" tier). setup = one-time, monthly = recurring.
SERVICES = {
    "website":   {"name": "Custom website (up to 5 pages, mobile-friendly)", "setup": 900, "monthly": 0},
    "landing":   {"name": "One-page website", "setup": 450, "monthly": 0},
    "chatbot":   {"name": "AI chatbot that answers customer questions 24/7", "setup": 350, "monthly": 59},
    "booking":   {"name": "Online booking / ordering system", "setup": 300, "monthly": 0},
    "gbp":       {"name": "Google Business Profile optimization", "setup": 200, "monthly": 0},
    "reviews":   {"name": "Automatic review requests & AI review replies", "setup": 150, "monthly": 49},
    "hosting":   {"name": "Hosting, updates & support", "setup": 0, "monthly": 39},
}

TIERS = {
    # name: (max estimated yearly revenue, price multiplier)
    "starter": (250_000, 0.7),
    "growth":  (900_000, 1.0),
    "premium": (float("inf"), 1.6),
}

# Very rough average yearly revenue of a small independent business in each category (USD).
CATEGORY_REVENUE = {
    "restaurant": 700_000, "cafe": 350_000, "bakery": 300_000, "bar": 500_000, "food truck": 200_000,
    "plumber": 450_000, "electrician": 450_000, "hvac": 650_000, "roofer": 700_000, "contractor": 600_000,
    "landscap": 300_000, "cleaning": 250_000, "pest": 350_000, "auto repair": 550_000, "mechanic": 500_000,
    "salon": 250_000, "barber": 180_000, "nail": 200_000, "spa": 400_000, "tattoo": 250_000,
    "dentist": 900_000, "chiropract": 500_000, "vet": 1_000_000, "gym": 400_000, "fitness": 300_000,
    "law": 800_000, "account": 500_000, "real estate": 400_000, "insurance": 450_000,
    "florist": 250_000, "pet": 250_000, "photograph": 120_000, "daycare": 400_000,
}
DEFAULT_REVENUE = 350_000


def estimate_revenue(category: str, reviews: int, price_level: int | None) -> int:
    cat = (category or "").lower()
    base = next((v for k, v in CATEGORY_REVENUE.items() if k in cat), DEFAULT_REVENUE)
    # More Google reviews ≈ more customers
    if reviews < 10:
        popularity = 0.5
    elif reviews < 50:
        popularity = 0.8
    elif reviews < 200:
        popularity = 1.0
    elif reviews < 500:
        popularity = 1.5
    else:
        popularity = 2.3
    price = {1: 0.8, 2: 1.0, 3: 1.4, 4: 2.0}.get(price_level or 2, 1.0)
    return int(round(base * popularity * price, -3))


def tier_for(revenue: int) -> str:
    for name, (ceiling, _) in TIERS.items():
        if revenue <= ceiling:
            return name
    return "premium"


def recommend_services(has_website: bool, issues: list[str]) -> list[str]:
    if not has_website:
        return ["website", "booking", "chatbot", "gbp", "hosting"]
    if len(issues) >= 3:  # weak site: rebuild it
        return ["website", "chatbot", "gbp", "hosting"]
    # their site is OK: sell add-ons instead
    picks = ["chatbot", "reviews", "gbp"]
    if any("booking" in i.lower() for i in issues):
        picks.append("booking")
    return picks


def quote(tier: str, service_keys: list[str]) -> dict:
    mult = TIERS.get(tier, TIERS["growth"])[1]
    lines = []
    for key in service_keys:
        svc = SERVICES.get(key)
        if not svc:
            continue
        lines.append({
            "key": key, "name": svc["name"],
            "setup": _round_price(svc["setup"] * mult), "monthly": _round_price(svc["monthly"] * mult),
        })
    setup = sum(l["setup"] for l in lines)
    monthly = sum(l["monthly"] for l in lines)
    # Bundle discount when they take 3+ services
    discount = round(setup * 0.15) if len(lines) >= 3 else 0
    return {"tier": tier, "lines": lines, "setup_total": setup, "discount": discount,
            "setup_due": setup - discount, "monthly_total": monthly}


def _round_price(x: float) -> int:
    """Charm pricing: 437 -> 449, 1012 -> 999."""
    if x <= 0:
        return 0
    if x < 100:
        return int(round(x / 5) * 5) - 1 if x > 10 else int(x)
    return int(round(x / 50) * 50) - 1
