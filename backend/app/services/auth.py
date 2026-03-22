import secrets
import hashlib
from datetime import datetime, timedelta, timezone

from jose import jwt, JWTError
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models import OTPCode, User

settings = get_settings()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def generate_otp() -> str:
    """Generate a random 6-digit OTP."""
    return "".join([str(secrets.randbelow(10)) for _ in range(settings.otp_length)])


def hash_otp(otp: str) -> str:
    """Hash an OTP using SHA-256 (fast; OTPs are short-lived so bcrypt is overkill)."""
    return hashlib.sha256(otp.encode()).hexdigest()


def verify_otp(plain_otp: str, hashed_otp: str) -> bool:
    return hash_otp(plain_otp) == hashed_otp


def create_otp(db: Session, phone_number: str) -> str:
    """Create and store a new OTP for a phone number. Returns the plain OTP."""
    # Invalidate any existing unused OTPs for this phone
    db.query(OTPCode).filter(
        OTPCode.phone_number == phone_number,
        OTPCode.used == False,
    ).update({"used": True})

    otp = generate_otp()
    otp_record = OTPCode(
        phone_number=phone_number,
        code_hash=hash_otp(otp),
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=settings.otp_expire_seconds),
    )
    db.add(otp_record)
    db.commit()
    return otp


def verify_otp_code(db: Session, phone_number: str, code: str) -> bool:
    """Verify an OTP code. Returns True if valid, marks it as used."""
    otp_record = (
        db.query(OTPCode)
        .filter(
            OTPCode.phone_number == phone_number,
            OTPCode.used == False,
            OTPCode.expires_at > datetime.now(timezone.utc),
        )
        .order_by(OTPCode.created_at.desc())
        .first()
    )
    if not otp_record:
        return False

    if not verify_otp(code, otp_record.code_hash):
        return False

    otp_record.used = True
    db.commit()
    return True


def get_or_create_user(db: Session, phone_number: str) -> User:
    """Get existing user or create a new one."""
    user = db.query(User).filter(User.phone_number == phone_number).first()
    if not user:
        user = User(phone_number=phone_number)
        db.add(user)
        db.commit()
        db.refresh(user)
    return user


def create_access_token(user_id: int) -> str:
    expires = datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_expire_minutes)
    payload = {
        "sub": str(user_id),
        "exp": expires,
        "type": "access",
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def create_refresh_token(user_id: int) -> str:
    expires = datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_expire_days)
    payload = {
        "sub": str(user_id),
        "exp": expires,
        "type": "refresh",
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict | None:
    """Decode and validate a JWT. Returns payload or None."""
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        return payload
    except JWTError:
        return None


# --- API Key auth ---

def generate_api_key() -> str:
    """Generate a random API key: nutrichat_live_ + 32 hex chars."""
    return f"nutrichat_live_{secrets.token_hex(16)}"


def hash_api_key(api_key: str) -> str:
    return pwd_context.hash(api_key)


def verify_api_key(plain_key: str, hashed_key: str) -> bool:
    return pwd_context.verify(plain_key, hashed_key)
