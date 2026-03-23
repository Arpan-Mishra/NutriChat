"""SMS/WhatsApp OTP delivery via Twilio.

In production, sends OTP codes via SMS or WhatsApp.
In debug mode (DEBUG=true), OTP is returned in the API response instead.
"""

import logging

from app.config import get_settings

logger = logging.getLogger(__name__)

# Lazy-loaded Twilio client (only imported when actually needed)
_twilio_client = None


def _get_twilio_client():
    """Lazy-load Twilio client to avoid import errors when Twilio isn't installed."""
    global _twilio_client
    if _twilio_client is None:
        try:
            from twilio.rest import Client

            settings = get_settings()
            _twilio_client = Client(
                settings.twilio_account_sid, settings.twilio_auth_token
            )
        except ImportError:
            logger.warning("twilio package not installed — SMS delivery disabled")
            return None
        except Exception as e:
            logger.error(f"Failed to initialize Twilio client: {e}")
            return None
    return _twilio_client


async def send_otp_sms(phone_number: str, otp_code: str) -> bool:
    """Send OTP via SMS using Twilio.

    Returns True if sent successfully, False otherwise.
    In debug mode, this is a no-op (OTP returned in API response instead).
    """
    settings = get_settings()

    if settings.debug:
        logger.info(f"Debug mode — skipping SMS delivery for {phone_number}")
        return True

    client = _get_twilio_client()
    if client is None:
        logger.error("Twilio client not available — cannot send SMS")
        return False

    try:
        message = client.messages.create(
            body=f"Your NutriChat verification code is: {otp_code}. Valid for 5 minutes.",
            from_=settings.twilio_phone_number,
            to=phone_number,
        )
        logger.info(f"OTP SMS sent to {phone_number}, SID: {message.sid}")
        return True
    except Exception as e:
        logger.error(f"Failed to send OTP SMS to {phone_number}: {e}")
        return False


async def send_otp_whatsapp(phone_number: str, otp_code: str) -> bool:
    """Send OTP via WhatsApp using Twilio.

    Returns True if sent successfully, False otherwise.
    In debug mode, this is a no-op.
    """
    settings = get_settings()

    if settings.debug:
        logger.info(f"Debug mode — skipping WhatsApp delivery for {phone_number}")
        return True

    client = _get_twilio_client()
    if client is None:
        logger.error("Twilio client not available — cannot send WhatsApp message")
        return False

    try:
        message = client.messages.create(
            body=f"Your NutriChat verification code is: {otp_code}. Valid for 5 minutes.",
            from_=f"whatsapp:{settings.twilio_phone_number}",
            to=f"whatsapp:{phone_number}",
        )
        logger.info(f"OTP WhatsApp sent to {phone_number}, SID: {message.sid}")
        return True
    except Exception as e:
        logger.error(f"Failed to send OTP WhatsApp to {phone_number}: {e}")
        return False
