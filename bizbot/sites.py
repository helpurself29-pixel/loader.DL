"""Template-based websites: used for the public showcase and as the no-API-key sample site."""
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape

from .config import settings

_env = Environment(loader=FileSystemLoader(Path(__file__).parent / "site_templates"),
                   autoescape=select_autoescape(["html"]))

PALETTES = {
    "food":    {"primary": "#b5452a", "accent": "#f2b134", "bg": "#fff8f0", "ink": "#2b1a12"},
    "trades":  {"primary": "#1d4e89", "accent": "#f28f3b", "bg": "#f5f8fc", "ink": "#14213d"},
    "beauty":  {"primary": "#8e4a7a", "accent": "#e8b4bc", "bg": "#fdf6f8", "ink": "#3a1f33"},
    "health":  {"primary": "#1b7a6e", "accent": "#7fd1b9", "bg": "#f3fbf9", "ink": "#0f2e2a"},
    "default": {"primary": "#33415c", "accent": "#5fa8d3", "bg": "#f7f9fb", "ink": "#1b263b"},
}
CATEGORY_GROUPS = {
    "food": ["restaurant", "cafe", "bakery", "bar", "food", "pizza", "taco", "diner", "coffee"],
    "trades": ["plumb", "electric", "hvac", "roof", "contract", "landscap", "clean", "pest", "auto", "mechanic"],
    "beauty": ["salon", "barber", "nail", "spa", "tattoo", "beauty", "lash"],
    "health": ["dent", "chiro", "vet", "gym", "fitness", "clinic", "therap", "massage"],
}
SERVICE_IDEAS = {
    "food": ["Dine-in", "Takeout & pickup", "Catering", "Daily specials"],
    "trades": ["Emergency service", "Repairs", "Installations", "Free estimates"],
    "beauty": ["Cuts & styling", "Color", "Treatments", "Walk-ins welcome"],
    "health": ["New patients welcome", "Consultations", "Same-week appointments", "Most insurance accepted"],
    "default": ["Our services", "Free consultations", "Fast turnaround", "Locally owned"],
}

SHOWCASE = [
    {"slug": "rosas-kitchen", "name": "Rosa's Kitchen", "category": "restaurant", "city": "Austin, TX",
     "phone": "(512) 555-0142", "rating": 4.7, "reviews": 312},
    {"slug": "summit-plumbing", "name": "Summit Plumbing & Drain", "category": "plumber", "city": "Denver, CO",
     "phone": "(303) 555-0187", "rating": 4.9, "reviews": 188},
    {"slug": "luxe-hair-studio", "name": "Luxe Hair Studio", "category": "salon", "city": "Tampa, FL",
     "phone": "(813) 555-0110", "rating": 4.8, "reviews": 96},
]


def group_for(category: str) -> str:
    cat = (category or "").lower()
    return next((g for g, words in CATEGORY_GROUPS.items() if any(w in cat for w in words)), "default")


def render_template_site(lead, banner: bool = True) -> str:
    group = group_for(lead["category"])
    return _env.get_template("business.html").render(
        b=dict(lead), colors=PALETTES[group], services=SERVICE_IDEAS[group],
        company=settings.company_name, banner=banner,
    )
