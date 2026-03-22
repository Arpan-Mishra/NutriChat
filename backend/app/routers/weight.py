from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User, WeightLog
from app.middleware.auth import get_current_user_flexible
from app.schemas import WeightLogCreate, WeightLogResponse

router = APIRouter(prefix="/api/v1/weight", tags=["weight"])


@router.post("/", response_model=WeightLogResponse, status_code=201)
async def log_weight(
    body: WeightLogCreate,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Log a new weight entry. Also updates the user's current weight."""
    log = WeightLog(
        user_id=user.id,
        weight_kg=body.weight_kg,
        notes=body.notes,
    )
    db.add(log)

    # Update user's current weight
    user.weight_kg = body.weight_kg
    db.commit()
    db.refresh(log)
    return log


@router.get("/", response_model=list[WeightLogResponse])
async def get_weight_history(
    limit: int = Query(30, ge=1, le=365),
    offset: int = Query(0, ge=0),
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Get weight history, most recent first."""
    logs = (
        db.query(WeightLog)
        .filter(WeightLog.user_id == user.id)
        .order_by(WeightLog.logged_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return logs


@router.delete("/{log_id}", status_code=204)
async def delete_weight_log(
    log_id: int,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Delete a weight log entry."""
    log = (
        db.query(WeightLog)
        .filter(WeightLog.id == log_id, WeightLog.user_id == user.id)
        .first()
    )
    if not log:
        raise HTTPException(status_code=404, detail="Weight log not found")

    db.delete(log)
    db.commit()
