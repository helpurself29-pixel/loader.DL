"""All settings come from environment variables or a .env file (see .env.example)."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # --- Your company (shown in emails, quotes and the CAN-SPAM footer) ---
    company_name: str = "BrightPath Digital"
    company_tagline: str = "Websites, chatbots and automation for local businesses"
    owner_name: str = "Alex"
    owner_email: str = ""            # where hot-lead alerts go
    owner_phone: str = ""
    company_address: str = ""        # physical mailing address, legally required for cold email (CAN-SPAM)

    # --- Public URL of this app (sample sites, showcase and unsubscribe links point here) ---
    public_base_url: str = "http://localhost:8000"
    dashboard_password: str = "change-me"

    # --- Safety switches ---
    dry_run: bool = True             # True = emails are logged in the dashboard, never actually sent
    daily_send_limit: int = 30       # max cold emails per day (protects your domain reputation)
    followup_days: int = 4           # days before the single follow-up
    max_followups: int = 1
    autopilot: bool = False          # run the full cycle automatically in the background
    cycle_minutes: int = 15

    # --- Claude ---
    anthropic_api_key: str = ""
    claude_model: str = "claude-opus-5-5"

    # --- Google Places (finding businesses) ---
    google_places_api_key: str = ""

    # --- Outgoing mail (SMTP) ---
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    from_email: str = ""

    # --- Incoming mail (IMAP, for reading replies) ---
    imap_host: str = ""
    imap_port: int = 993
    imap_user: str = ""
    imap_password: str = ""

    # --- Optional phone alerts ---
    ntfy_topic: str = ""             # free push notifications via the ntfy app (ntfy.sh)
    discord_webhook_url: str = ""

    database_path: str = "bizbot.db"

    @property
    def demo_mode(self) -> bool:
        """No Places key → use built-in sample businesses so the app can be tried end to end."""
        return not self.google_places_api_key


settings = Settings()
