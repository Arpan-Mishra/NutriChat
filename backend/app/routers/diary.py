from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User, MealEntry, FoodItem, FoodServing
from app.schemas import (
    MealEntryCreate,
    MealEntryResponse,
    MealEntryUpdate,
    DayDiaryResponse,
)
from app.middleware.auth import get_current_user_flexible

# Standard unit conversions (approximate gram equivalents for generic foods)
STANDARD_UNIT_GRAMS = {
    "g": 1.0,
    "ml": 1.0,
    "cup": 240.0,
    "tbsp": 15.0,
    "tsp": 5.0,
    "piece": 100.0,
    "serving": 100.0,
}

router = APIRouter(prefix="/api/v1/diary", tags=["diary"])


def _compute_macros_from_food(food: FoodItem, serving_g: float) -> dict:
    """Compute macros for a given serving size from per-100g values."""
    factor = serving_g / 100.0
    return {
        "calories": round(food.calories_per_100g * factor, 1),
        "protein_g": round(food.protein_per_100g * factor, 1),
        "fat_g": round(food.fat_per_100g * factor, 1),
        "carbs_g": round(food.carbs_per_100g * factor, 1),
        "fiber_g": round(food.fiber_per_100g * factor, 1),
        "sodium_mg": round(food.sodium_per_100g * factor, 1),
    }


@router.post("/entries", response_model=MealEntryResponse, status_code=201)
async def create_entry(
    body: MealEntryCreate,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Log a food entry to the diary."""
    serving_size_g = body.serving_size_g

    # Resolve unit → grams if unit + quantity provided
    if body.serving_unit and body.serving_quantity and body.food_item_id:
        serving_size_g = _resolve_serving_grams(
            db, body.food_item_id, body.serving_unit, body.serving_quantity
        )
    elif body.serving_unit and body.serving_quantity:
        # No food item — use standard conversion
        grams_per_unit = STANDARD_UNIT_GRAMS.get(body.serving_unit, 1.0)
        serving_size_g = grams_per_unit * body.serving_quantity

    entry_data = {
        "user_id": user.id,
        "meal_type": body.meal_type,
        "food_description": body.food_description,
        "serving_size_g": serving_size_g,
        "serving_unit": body.serving_unit,
        "serving_quantity": body.serving_quantity,
        "source": body.source,
        "logged_date": body.logged_date or date.today(),
        "food_item_id": body.food_item_id,
    }

    # Auto-compute macros from food_item if linked and macros not provided
    if body.food_item_id:
        food = db.query(FoodItem).filter(FoodItem.id == body.food_item_id).first()
        if not food:
            raise HTTPException(status_code=404, detail="Food item not found")
        computed = _compute_macros_from_food(food, serving_size_g)
        entry_data["calories"] = body.calories if body.calories is not None else computed["calories"]
        entry_data["protein_g"] = body.protein_g if body.protein_g is not None else computed["protein_g"]
        entry_data["fat_g"] = body.fat_g if body.fat_g is not None else computed["fat_g"]
        entry_data["carbs_g"] = body.carbs_g if body.carbs_g is not None else computed["carbs_g"]
        entry_data["fiber_g"] = body.fiber_g if body.fiber_g is not None else computed["fiber_g"]
        entry_data["sodium_mg"] = body.sodium_mg if body.sodium_mg is not None else computed["sodium_mg"]
    else:
        entry_data["calories"] = body.calories or 0
        entry_data["protein_g"] = body.protein_g or 0
        entry_data["fat_g"] = body.fat_g or 0
        entry_data["carbs_g"] = body.carbs_g or 0
        entry_data["fiber_g"] = body.fiber_g or 0
        entry_data["sodium_mg"] = body.sodium_mg or 0

    entry = MealEntry(**entry_data)
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


@router.get("/{diary_date}", response_model=DayDiaryResponse)
async def get_day(
    diary_date: date,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Get all diary entries for a specific date, grouped by meal type."""
    entries = (
        db.query(MealEntry)
        .filter(MealEntry.user_id == user.id, MealEntry.logged_date == diary_date)
        .order_by(MealEntry.logged_at)
        .all()
    )

    meals: dict[str, list] = {
        "breakfast": [],
        "lunch": [],
        "dinner": [],
        "snack": [],
    }
    totals = {"calories": 0.0, "protein_g": 0.0, "fat_g": 0.0, "carbs_g": 0.0}

    for entry in entries:
        if entry.meal_type in meals:
            meals[entry.meal_type].append(entry)
        totals["calories"] += entry.calories
        totals["protein_g"] += entry.protein_g
        totals["fat_g"] += entry.fat_g
        totals["carbs_g"] += entry.carbs_g

    # Round totals
    totals = {k: round(v, 1) for k, v in totals.items()}

    goals = {
        "calorie_goal": user.daily_calorie_goal,
        "protein_goal": user.protein_goal_g,
        "carbs_goal": user.carbs_goal_g,
        "fat_goal": user.fat_goal_g,
    }

    progress_pct = {}
    goal_map = {
        "calories": user.daily_calorie_goal,
        "protein_g": user.protein_goal_g,
        "fat_g": user.fat_goal_g,
        "carbs_g": user.carbs_goal_g,
    }
    for key, goal_val in goal_map.items():
        if goal_val and goal_val > 0:
            progress_pct[key] = round(totals[key] / goal_val * 100, 1)
        else:
            progress_pct[key] = None

    return DayDiaryResponse(
        date=diary_date,
        meals=meals,
        totals=totals,
        goals=goals,
        progress_pct=progress_pct,
    )


@router.patch("/entries/{entry_id}", response_model=MealEntryResponse)
async def update_entry(
    entry_id: int,
    body: MealEntryUpdate,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Update a diary entry (meal type, serving size, description)."""
    entry = (
        db.query(MealEntry)
        .filter(MealEntry.id == entry_id, MealEntry.user_id == user.id)
        .first()
    )
    if not entry:
        raise HTTPException(status_code=404, detail="Entry not found")

    if body.meal_type is not None:
        entry.meal_type = body.meal_type
    if body.food_description is not None:
        entry.food_description = body.food_description

    # If serving size changes and entry is linked to a food item, recompute macros
    if body.serving_size_g is not None:
        entry.serving_size_g = body.serving_size_g
        if entry.food_item_id:
            food = db.query(FoodItem).filter(FoodItem.id == entry.food_item_id).first()
            if food:
                computed = _compute_macros_from_food(food, body.serving_size_g)
                entry.calories = computed["calories"]
                entry.protein_g = computed["protein_g"]
                entry.fat_g = computed["fat_g"]
                entry.carbs_g = computed["carbs_g"]
                entry.fiber_g = computed["fiber_g"]
                entry.sodium_mg = computed["sodium_mg"]

    db.commit()
    db.refresh(entry)
    return entry


@router.delete("/entries/{entry_id}", status_code=204)
async def delete_entry(
    entry_id: int,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Delete a diary entry."""
    entry = (
        db.query(MealEntry)
        .filter(MealEntry.id == entry_id, MealEntry.user_id == user.id)
        .first()
    )
    if not entry:
        raise HTTPException(status_code=404, detail="Entry not found")

    db.delete(entry)
    db.commit()


def _resolve_serving_grams(
    db: Session, food_item_id: int, unit: str, quantity: float
) -> float:
    """Look up gram equivalent for a unit from food_servings, fallback to standard."""
    # Try to find a matching FoodServing for this food
    servings = (
        db.query(FoodServing)
        .filter(FoodServing.food_item_id == food_item_id)
        .all()
    )
    for s in servings:
        desc = s.serving_description.lower()
        if unit in desc or (unit == "cup" and "cup" in desc) or (unit == "tbsp" and "tbsp" in desc):
            return s.serving_size_g * quantity

    # Fallback to standard conversion
    grams_per_unit = STANDARD_UNIT_GRAMS.get(unit, 1.0)
    return grams_per_unit * quantity
