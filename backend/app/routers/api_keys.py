from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User, ApiKey
from app.schemas import ApiKeyCreate, ApiKeyResponse, ApiKeyCreated
from app.middleware.auth import get_current_user
from app.services.auth import generate_api_key, hash_api_key

router = APIRouter(prefix="/api/v1/apikeys", tags=["api-keys"])


@router.post("/", response_model=ApiKeyCreated, status_code=201)
async def create_api_key(
    body: ApiKeyCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Generate a new API key. The raw key is returned only once."""
    raw_key = generate_api_key()
    key_hash = hash_api_key(raw_key)
    prefix = raw_key[:20]  # nutrichat_live_ + first 5 hex chars

    api_key = ApiKey(
        user_id=user.id,
        key_prefix=prefix,
        key_hash=key_hash,
        label=body.label,
    )
    db.add(api_key)
    db.commit()
    db.refresh(api_key)

    return ApiKeyCreated(
        id=api_key.id,
        api_key=raw_key,
        label=api_key.label,
        created_at=api_key.created_at,
    )


@router.get("/", response_model=list[ApiKeyResponse])
async def list_api_keys(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List all API keys for the current user (active and revoked)."""
    keys = (
        db.query(ApiKey)
        .filter(ApiKey.user_id == user.id)
        .order_by(ApiKey.created_at.desc())
        .all()
    )
    return keys


@router.delete("/{key_id}", status_code=204)
async def revoke_api_key(
    key_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Revoke an API key (soft delete — sets revoked_at)."""
    api_key = (
        db.query(ApiKey)
        .filter(ApiKey.id == key_id, ApiKey.user_id == user.id)
        .first()
    )
    if not api_key:
        raise HTTPException(status_code=404, detail="API key not found")

    if api_key.revoked_at:
        raise HTTPException(status_code=400, detail="API key already revoked")

    api_key.revoked_at = datetime.now(timezone.utc)
    db.commit()
