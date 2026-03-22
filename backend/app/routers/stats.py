from datetime import date, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User, MealEntry
from app.middleware.auth import get_current_user_flexible
from app.schemas import DailyStatsResponse, WeeklyStatsResponse

router = APIRouter(prefix="/api/v1/stats", tags=["stats"])


@router.get("/daily", response_model=DailyStatsResponse)
async def daily_stats(
    stats_date: date = Query(default=None, alias="date", description="Date (YYYY-MM-DD), defaults to today"),
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Get calorie and macro totals for a specific day."""
    target_date = stats_date or date.today()

    row = (
        db.query(
            func.coalesce(func.sum(MealEntry.calories), 0).label("calories"),
            func.coalesce(func.sum(MealEntry.protein_g), 0).label("protein_g"),
            func.coalesce(func.sum(MealEntry.fat_g), 0).label("fat_g"),
            func.coalesce(func.sum(MealEntry.carbs_g), 0).label("carbs_g"),
            func.count(MealEntry.id).label("entry_count"),
        )
        .filter(MealEntry.user_id == user.id, MealEntry.logged_date == target_date)
        .first()
    )

    calories = round(float(row.calories), 1)
    protein_g = round(float(row.protein_g), 1)
    fat_g = round(float(row.fat_g), 1)
    carbs_g = round(float(row.carbs_g), 1)

    goal_pct = None
    if user.daily_calorie_goal and user.daily_calorie_goal > 0:
        goal_pct = round(calories / user.daily_calorie_goal * 100, 1)

    return DailyStatsResponse(
        date=target_date,
        calories=calories,
        protein_g=protein_g,
        fat_g=fat_g,
        carbs_g=carbs_g,
        entry_count=row.entry_count,
        calorie_goal=user.daily_calorie_goal,
        calorie_goal_pct=goal_pct,
    )


@router.get("/weekly", response_model=WeeklyStatsResponse)
async def weekly_stats(
    start_date: date = Query(default=None, description="Start date (YYYY-MM-DD), defaults to 7 days ago"),
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Get average daily calories and macros over a week."""
    end = date.today()
    start = start_date or (end - timedelta(days=6))
    num_days = (end - start).days + 1

    row = (
        db.query(
            func.coalesce(func.sum(MealEntry.calories), 0).label("calories"),
            func.coalesce(func.sum(MealEntry.protein_g), 0).label("protein_g"),
            func.coalesce(func.sum(MealEntry.fat_g), 0).label("fat_g"),
            func.coalesce(func.sum(MealEntry.carbs_g), 0).label("carbs_g"),
            func.count(MealEntry.id).label("entry_count"),
        )
        .filter(
            MealEntry.user_id == user.id,
            MealEntry.logged_date >= start,
            MealEntry.logged_date <= end,
        )
        .first()
    )

    total_cal = float(row.calories)
    total_protein = float(row.protein_g)
    total_fat = float(row.fat_g)
    total_carbs = float(row.carbs_g)

    # Days with at least one entry
    days_logged = (
        db.query(func.count(func.distinct(MealEntry.logged_date)))
        .filter(
            MealEntry.user_id == user.id,
            MealEntry.logged_date >= start,
            MealEntry.logged_date <= end,
        )
        .scalar()
    )

    avg_divisor = max(days_logged, 1)

    return WeeklyStatsResponse(
        start_date=start,
        end_date=end,
        total_days=num_days,
        days_logged=days_logged,
        total_calories=round(total_cal, 1),
        avg_calories=round(total_cal / avg_divisor, 1),
        avg_protein_g=round(total_protein / avg_divisor, 1),
        avg_fat_g=round(total_fat / avg_divisor, 1),
        avg_carbs_g=round(total_carbs / avg_divisor, 1),
        total_entries=row.entry_count,
        calorie_goal=user.daily_calorie_goal,
    )
