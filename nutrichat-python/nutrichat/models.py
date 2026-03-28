"""Pydantic models for NutriChat API responses."""

from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel


class FoodServing(BaseModel):
    id: int
    serving_description: str
    serving_size_g: float
    metric_serving_amount: Optional[float] = None
    metric_serving_unit: Optional[str] = None
    is_default: bool = False


class FoodItem(BaseModel):
    food_id: int
    food_name: str
    brand: Optional[str] = None
    source: str
    calories_per_100g: float
    protein_per_100g: float
    fat_per_100g: float
    carbs_per_100g: float
    serving_size_g: float
    serving_description: str
    servings: list[FoodServing] = []


class MealEntry(BaseModel):
    id: int
    user_id: int
    food_item_id: Optional[int] = None
    meal_type: str
    food_description: str
    serving_size_g: float
    serving_unit: Optional[str] = None
    serving_quantity: Optional[float] = None
    calories: float
    protein_g: float
    fat_g: float
    carbs_g: float
    fiber_g: float
    sodium_mg: float
    source: str
    logged_date: date
    logged_at: datetime


class DailyTotals(BaseModel):
    calories: float
    protein_g: float
    fat_g: float
    carbs_g: float
