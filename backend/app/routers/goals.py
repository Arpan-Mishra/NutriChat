from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User, Goal
from app.middleware.auth import get_current_user_flexible
from app.schemas import GoalCreate, GoalResponse, GoalUpdate

router = APIRouter(prefix="/api/v1/goals", tags=["goals"])


@router.post("/", response_model=GoalResponse, status_code=201)
async def create_goal(
    body: GoalCreate,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Create a new goal. Deactivates any existing active goal of the same type."""
    # Deactivate existing active goals of the same type
    db.query(Goal).filter(
        Goal.user_id == user.id,
        Goal.goal_type == body.goal_type,
        Goal.active == True,
    ).update({"active": False})

    goal = Goal(
        user_id=user.id,
        goal_type=body.goal_type,
        target_value=body.target_value,
        unit=body.unit,
        start_date=body.start_date,
        end_date=body.end_date,
    )
    db.add(goal)
    db.commit()
    db.refresh(goal)
    return goal


@router.get("/", response_model=list[GoalResponse])
async def list_goals(
    active_only: bool = True,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """List user's goals. By default only active goals."""
    query = db.query(Goal).filter(Goal.user_id == user.id)
    if active_only:
        query = query.filter(Goal.active == True)
    return query.order_by(Goal.created_at.desc()).all()


@router.patch("/{goal_id}", response_model=GoalResponse)
async def update_goal(
    goal_id: int,
    body: GoalUpdate,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Update a goal's target or active status."""
    goal = (
        db.query(Goal)
        .filter(Goal.id == goal_id, Goal.user_id == user.id)
        .first()
    )
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")

    if body.target_value is not None:
        goal.target_value = body.target_value
    if body.active is not None:
        goal.active = body.active
    if body.end_date is not None:
        goal.end_date = body.end_date

    db.commit()
    db.refresh(goal)
    return goal


@router.delete("/{goal_id}", status_code=204)
async def delete_goal(
    goal_id: int,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Delete a goal."""
    goal = (
        db.query(Goal)
        .filter(Goal.id == goal_id, Goal.user_id == user.id)
        .first()
    )
    if not goal:
        raise HTTPException(status_code=404, detail="Goal not found")

    db.delete(goal)
    db.commit()
