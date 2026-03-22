from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User
from app.schemas import UserProfile, UserUpdate, TDEEResponse
from app.middleware.auth import get_current_user
from app.services.tdee import compute_tdee_for_user

router = APIRouter(prefix="/api/v1/users", tags=["users"])


@router.get("/me", response_model=UserProfile)
async def get_me(user: User = Depends(get_current_user)):
    return user


@router.patch("/me", response_model=UserProfile)
async def update_me(
    body: UserUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    update_data = body.model_dump(exclude_unset=True)

    for field, value in update_data.items():
        setattr(user, field, value)

    # Auto-recompute calorie goal if body stats or goal_type changed
    stat_fields = {"weight_kg", "height_cm", "activity_level", "goal_type", "date_of_birth", "sex"}
    if stat_fields & update_data.keys():
        if all([user.weight_kg, user.height_cm, user.date_of_birth, user.sex, user.activity_level]):
            tdee_data = compute_tdee_for_user(
                weight_kg=user.weight_kg,
                height_cm=user.height_cm,
                dob=user.date_of_birth,
                sex=user.sex,
                activity_level=user.activity_level,
                goal_type=user.goal_type or "maintain",
            )
            # Only auto-set if user hasn't manually overridden
            if "daily_calorie_goal" not in update_data:
                user.daily_calorie_goal = tdee_data["recommended_calories"]

    db.commit()
    db.refresh(user)
    return user


@router.get("/me/tdee", response_model=TDEEResponse)
async def get_tdee(user: User = Depends(get_current_user)):
    """Get computed BMR and TDEE based on current profile."""
    if not all([user.weight_kg, user.height_cm, user.date_of_birth, user.sex, user.activity_level]):
        raise HTTPException(
            status_code=400,
            detail="Profile incomplete. Set weight, height, date_of_birth, sex, and activity_level first.",
        )

    return compute_tdee_for_user(
        weight_kg=user.weight_kg,
        height_cm=user.height_cm,
        dob=user.date_of_birth,
        sex=user.sex,
        activity_level=user.activity_level,
        goal_type=user.goal_type or "maintain",
    )
