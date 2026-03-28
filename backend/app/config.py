from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # App
    app_name: str = "NutriChat"
    debug: bool = False

    # Database
    database_url: str = "postgresql://localhost:5432/nutrichat"

    # JWT
    jwt_secret_key: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60
    refresh_token_expire_days: int = 30

    # OTP
    otp_expire_seconds: int = 300  # 5 minutes
    otp_length: int = 6

    # External APIs
    usda_api_key: str = ""
    edamam_app_id: str = ""
    edamam_app_key: str = ""

    # FatSecret Food Database
    fatsecret_consumer_key: str = ""
    fatsecret_consumer_secret: str = ""

    # Twilio (SMS/WhatsApp OTP delivery)
    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    twilio_phone_number: str = ""

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


@lru_cache
def get_settings() -> Settings:
    return Settings()
