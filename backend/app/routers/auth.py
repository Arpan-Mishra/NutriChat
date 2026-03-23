import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import get_db
from app.schemas import OTPRequest, OTPVerify, TokenResponse, RefreshRequest
from app.services.auth import (
    create_otp,
    verify_otp_code,
    get_or_create_user,
    create_access_token,
    create_refresh_token,
    decode_token,
)
from app.services.sms import send_otp_sms

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


@router.post("/otp/request")
async def request_otp(body: OTPRequest, db: Session = Depends(get_db)):
    """Generate an OTP and send it via SMS.
    In debug mode, the OTP is also returned in the response for testing."""
    settings = get_settings()
    otp = create_otp(db, body.phone_number)
    logger.info(f"OTP generated for {body.phone_number}")

    # Send OTP via SMS (no-op in debug mode)
    sent = await send_otp_sms(body.phone_number, otp)
    if not sent and not settings.debug:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send OTP. Please try again.",
        )

    response = {
        "message": "OTP sent successfully",
        "expires_in": settings.otp_expire_seconds,
    }

    # Only include OTP in response when in debug mode
    if settings.debug:
        response["otp_debug"] = otp

    return response


@router.post("/otp/verify", response_model=TokenResponse)
async def verify_otp(body: OTPVerify, db: Session = Depends(get_db)):
    """Verify OTP and return JWT tokens. Creates user if new."""
    is_valid = verify_otp_code(db, body.phone_number, body.code)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired OTP",
        )

    user = get_or_create_user(db, body.phone_number)
    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(body: RefreshRequest):
    """Exchange a refresh token for a new access + refresh token pair."""
    payload = decode_token(body.refresh_token)
    if not payload or payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    user_id = int(payload["sub"])
    access_token = create_access_token(user_id)
    new_refresh_token = create_refresh_token(user_id)

    return TokenResponse(
        access_token=access_token,
        refresh_token=new_refresh_token,
    )


@router.post("/logout")
async def logout():
    """Logout. Client should discard tokens.
    In a production system, you'd blacklist the refresh token here."""
    return {"message": "Logged out successfully"}
