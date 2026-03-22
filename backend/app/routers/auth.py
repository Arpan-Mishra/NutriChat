import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

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

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


@router.post("/otp/request")
async def request_otp(body: OTPRequest, db: Session = Depends(get_db)):
    """Generate and return an OTP for the given phone number.
    In production, this would send the OTP via WhatsApp/SMS.
    For development, the OTP is returned directly in the response."""
    otp = create_otp(db, body.phone_number)
    logger.info(f"OTP generated for {body.phone_number}")

    # In production: send OTP via WhatsApp/SMS and don't include it in response
    # For development: return it directly so we can test without SMS
    return {
        "message": "OTP sent successfully",
        "expires_in": 300,
        "otp_debug": otp,  # REMOVE IN PRODUCTION
    }


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
